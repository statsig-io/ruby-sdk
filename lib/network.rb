# typed: true

require 'http'
require 'json'
require 'securerandom'
require 'sorbet-runtime'
require 'uri_helper'
require 'connection_pool'

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
    extend T::Sig

    sig { params(server_secret: String, options: StatsigOptions, backoff_mult: Integer).void }

    def initialize(server_secret, options, backoff_mult = 10)
      super()
      URIHelper.initialize(options)
      @server_secret = server_secret
      @local_mode = options.local_mode
      @timeout = options.network_timeout
      @backoff_multiplier = backoff_mult
      @post_logs_retry_backoff = options.post_logs_retry_backoff
      @post_logs_retry_limit = options.post_logs_retry_limit
      @session_id = SecureRandom.uuid
      @connection_pool = ConnectionPool.new(size: 3) do
        meta = Statsig.get_statsig_metadata
        client = HTTP.headers(
          {
            'STATSIG-API-KEY' => @server_secret,
            'STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s,
            'STATSIG-SERVER-SESSION-ID' => @session_id,
            'Content-Type' => 'application/json; charset=UTF-8',
            'STATSIG-SDK-TYPE' => meta['sdkType'],
            'STATSIG-SDK-VERSION' => meta['sdkVersion']
          }
        ).accept(:json)
        if @timeout
          client = client.timeout(@timeout)
        end

        client
      end
    end

    sig do
      params(endpoint: String, body: String, retries: Integer, backoff: Integer)
        .returns([T.any(HTTP::Response, NilClass), T.any(StandardError, NilClass)])
    end

    def post_helper(endpoint, body, retries = 0, backoff = 1)
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
      url = URIHelper.build_url(endpoint)
      begin
        res = @connection_pool.with do |conn|
          conn.headers('STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s).post(url, body: body)
        end
      rescue StandardError => e
        ## network error retry
        return nil, e unless retries.positive?

        sleep backoff_adjusted
        return post_helper(endpoint, body, retries - 1, backoff * @backoff_multiplier)
      end
      return res, nil if res.status.success?

      unless retries.positive? && RETRY_CODES.include?(res.code)
        return res, NetworkError.new("Got an exception when making request to #{url}: #{res.to_s}",
                                     res.status.to_i)
      end

      ## status code retry
      sleep backoff_adjusted
      post_helper(endpoint, body, retries - 1, backoff * @backoff_multiplier)
    end

    def check_gate(user, gate_name)
      request_body = JSON.generate({ 'user' => user&.serialize(false), 'gateName' => gate_name })
      response, = post_helper('check_gate', request_body)
      return JSON.parse(response.body) unless response.nil?

      false
    rescue StandardError
      false
    end

    def get_config(user, dynamic_config_name)
      request_body = JSON.generate({ 'user' => user&.serialize(false), 'configName' => dynamic_config_name })
      response, = post_helper('get_config', request_body)
      return JSON.parse(response.body) unless response.nil?

      nil
    rescue StandardError
      nil
    end

    def post_logs(events)
      json_body = JSON.generate({ 'events' => events, 'statsigMetadata' => Statsig.get_statsig_metadata })
      post_helper('log_event', json_body, @post_logs_retry_limit)
    rescue StandardError

    end
  end
end
