require 'connection_pool'
require 'http'
require 'json'
require 'securerandom'
require 'zlib'

RETRY_CODES = [408, 500, 502, 503, 504, 522, 524, 599].freeze

module Statsig
  STATSIG_CDN_DCS_BASE = 'https://api.statsigcdn.com/v2'.freeze
  class NetworkError < StandardError
    attr_reader :http_code

    def initialize(msg = nil, http_code = nil)
      super(msg)
      @http_code = http_code
    end
  end

  class Network

    def initialize(server_secret, options, backoff_mult = 10)
      super()
      @options = options
      @server_secret = server_secret
      @local_mode = options.local_mode
      @timeout = options.network_timeout
      @backoff_multiplier = backoff_mult
      @post_logs_retry_backoff = options.post_logs_retry_backoff
      @post_logs_retry_limit = options.post_logs_retry_limit
      @session_id = SecureRandom.uuid
      @connection_pools = {}
      @connection_pools_mutex = Mutex.new
    end

    def download_config_specs(since_time, context)
      url = @options.download_config_specs_url
      dcs_url = "#{url}#{@server_secret}.json"
      if since_time.positive?
        dcs_url += "?sinceTime=#{since_time}"
      end
      if context == 'initialize'
        return get(dcs_url, @options.initialize_retry_limit)
      end
      get(dcs_url)
    end

    def download_config_specs_fallback(since_time, context)
      dcs_url = "#{STATSIG_CDN_DCS_BASE}/download_config_specs/#{@server_secret}.json"
      if since_time.positive?
        dcs_url += "?sinceTime=#{since_time}"
      end
      get(dcs_url)
    end

    def post_logs(events, error_boundary)
      url = @options.log_event_url
      event_count = events.length
      json_body = JSON.generate({ events: events, statsigMetadata: Statsig.get_statsig_metadata })
      gzip = Zlib::GzipWriter.new(StringIO.new)
      gzip << json_body

      _response, e = post(url, gzip.close.string, @post_logs_retry_limit, 1, true, event_count)

      unless e == nil
        message = "Failed to log #{event_count} events after #{@post_logs_retry_limit} retries"
        puts "[Statsig]: #{message}"
        error_boundary.log_exception(e, tag: 'statsig::log_event_failed', extra: { eventCount: event_count, error: message }, force: true)
        return
      end
    rescue StandardError

    end

    def get_id_lists(context)
      url = @options.get_id_lists_url
      if context == 'initialize'
        return post(url, JSON.generate({ 'statsigMetadata' => Statsig.get_statsig_metadata }), @options.initialize_retry_limit)
      end
      post(url, JSON.generate({ 'statsigMetadata' => Statsig.get_statsig_metadata }))
    end

    def download_id_list(url, start_byte = 0)
      request(:GET, url, nil, 0, 1, false, 0, { 'Range' => "bytes=#{start_byte}-" }, false)
    end

    def get(url, retries = 0, backoff = 1)
      request(:GET, url, nil, retries, backoff)
    end

    def post(url, body, retries = 0, backoff = 1, zipped = false, event_count = 0)
      request(:POST, url, body, retries, backoff, zipped, event_count)
    end

    def shutdown
      pools = @connection_pools_mutex.synchronize do
        pools = @connection_pools.values
        @connection_pools = {}
        pools
      end

      pools.each do |pool|
        pool.shutdown do |conn|
          conn.close if conn.respond_to?(:close)
        end
      end
    end

    def request(method, url, body, retries = 0, backoff = 1, zipped = false, event_count = 0, extra_headers = {}, use_statsig_headers = true)
      if @local_mode
        return nil, nil
      end
      backoff_adjusted = backoff > 10 ? backoff += Random.rand(10) : backoff # to deter overlap
      if @post_logs_retry_backoff
        if @post_logs_retry_backoff.is_a? Integer
          backoff_adjusted = @post_logs_retry_backoff
        else
          backoff_adjusted = @post_logs_retry_backoff.call(retries)
        end
      end

      begin
        pool = connection_pool_for(url)
        res = pool.with do |conn|
          begin
            request_headers = build_request_headers(zipped, event_count, extra_headers, use_statsig_headers)
            request = conn.headers(request_headers)

            response = case method
                       when :GET
                         request.get(url)
                       when :POST
                         request.post(url, body: body)
                       end

            # Fully drain the response before the client returns to the pool.
            response.body.to_s
            response
          rescue StandardError
            pool.discard_current_connection(&:close)
            raise
          end
        end
      rescue StandardError => e
        ## network error retry
        return nil, e unless retries.positive?

        sleep backoff_adjusted
        return request(method, url, body, retries - 1, backoff * @backoff_multiplier, zipped, event_count, extra_headers, use_statsig_headers)
      end
      return res, nil if res.status.success?

      unless retries.positive? && RETRY_CODES.include?(res.code)
        return res, NetworkError.new("Got an exception when making request to #{url}: #{res.to_s}",
                                     res.status.to_i)
      end

      ## status code retry
      sleep backoff_adjusted
      request(method, url, body, retries - 1, backoff * @backoff_multiplier, zipped, event_count, extra_headers, use_statsig_headers)
    end

    private

    def connection_pool_for(url)
      origin = HTTP::URI.parse(url).origin
      @connection_pools_mutex.synchronize do
        @connection_pools[origin] ||= ConnectionPool.new(size: 3) do
          build_persistent_client(origin)
        end
      end
    end

    def build_persistent_client(origin)
      client = HTTP.use(:auto_inflate)
      client = client.timeout(@timeout) if @timeout
      client.persistent(origin)
    end

    def build_request_headers(zipped, event_count, extra_headers, use_statsig_headers)
      headers = {}

      if use_statsig_headers
        meta = Statsig.get_statsig_metadata
        headers.merge!(
          'STATSIG-API-KEY' => @server_secret,
          'STATSIG-SERVER-SESSION-ID' => @session_id,
          'Content-Type' => 'application/json; charset=UTF-8',
          'STATSIG-SDK-TYPE' => meta['sdkType'],
          'STATSIG-SDK-VERSION' => meta['sdkVersion'],
          'STATSIG-SDK-LANGUAGE-VERSION' => meta['languageVersion'],
          'Accept' => 'application/json',
          'Accept-Encoding' => 'gzip',
          'STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s
        )
      end

      headers['CONTENT-ENCODING'] = 'gzip' if zipped
      headers['STATSIG-EVENT-COUNT'] = event_count.to_s unless event_count == 0

      headers.merge!(extra_headers)
      headers.delete_if { |_key, value| value.nil? }
      headers
    end
  end
end
