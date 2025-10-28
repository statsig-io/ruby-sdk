require 'connection_pool'
require 'http'
require 'json'
require 'securerandom'
require 'zlib'

RETRY_CODES = [408, 500, 502, 503, 504, 522, 524, 599].freeze

module Statsig
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
      @ssl_context = options.ssl_context
      @session_id = SecureRandom.uuid
      @connection_pool = ConnectionPool.new(size: 3) do
        meta = Statsig.get_statsig_metadata
        client = HTTP.use(:auto_inflate).headers(
          {
            'STATSIG-API-KEY' => @server_secret,
            'STATSIG-SERVER-SESSION-ID' => @session_id,
            'Content-Type' => 'application/json; charset=UTF-8',
            'STATSIG-SDK-TYPE' => meta['sdkType'],
            'STATSIG-SDK-VERSION' => meta['sdkVersion'],
            'STATSIG-SDK-LANGUAGE-VERSION' => meta['languageVersion'],
            'Accept-Encoding' => 'gzip'
          }
        ).accept(:json)

        if @timeout
          client = client.timeout(@timeout)
        end

        client
      end
    end

    def download_config_specs(since_time)
      url = @options.download_config_specs_url
      dcs_url = "#{url}#{@server_secret}.json"
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

      response, e = post(url, gzip.close.string, @post_logs_retry_limit, 1, true, event_count)
      unless e == nil
        message = "Failed to log #{event_count} events after #{@post_logs_retry_limit} retries"
        puts "[Statsig]: #{message}"
        error_boundary.log_exception(e, tag: 'statsig::log_event_failed', extra: { eventCount: event_count, error: message }, force: true)
        return
      end
    rescue StandardError

    end

    def get_id_lists
      url = @options.get_id_lists_url
      post(url, JSON.generate({ 'statsigMetadata' => Statsig.get_statsig_metadata }))
    end

    def get(url, retries = 0, backoff = 1)
      request(:GET, url, nil, retries, backoff)
    end

    def post(url, body, retries = 0, backoff = 1, zipped = false, event_count = 0)
      request(:POST, url, body, retries, backoff, zipped, event_count)
    end

    def request(method, url, body, retries = 0, backoff = 1, zipped = false, event_count = 0)
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
        res = @connection_pool.with do |conn|
          request = conn.headers(
            'STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s,
            'CONTENT-ENCODING' => zipped ? 'gzip' : nil,
            'STATSIG-EVENT-COUNT' => event_count == 0 ? nil : event_count.to_s
          )

          options = {}
          if @ssl_context
            options[:ssl_context] = @ssl_context
          end

          case method
          when :GET
            request.get(url, **options)
          when :POST
            options[:body] = body
            request.post(url, **options)
          end
        end
      rescue StandardError => e
        ## network error retry
        return nil, e unless retries.positive?

        sleep backoff_adjusted
        return request(method, url, body, retries - 1, backoff * @backoff_multiplier, zipped, event_count)
      end
      return res, nil if res.status.success?

      unless retries.positive? && RETRY_CODES.include?(res.code)
        return res, NetworkError.new("Got an exception when making request to #{url}: #{res.to_s}",
                                     res.status.to_i)
      end

      ## status code retry
      sleep backoff_adjusted
      request(method, url, body, retries - 1, backoff * @backoff_multiplier, zipped, event_count)
    end
  end
end
