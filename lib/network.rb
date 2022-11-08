# typed: true

require 'http'
require 'json'
require 'securerandom'
require 'sorbet-runtime'

$retry_codes = [408, 500, 502, 503, 504, 522, 524, 599]

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

    sig { params(server_secret: String, api: String, local_mode: T::Boolean, backoff_mult: Integer).void }

    def initialize(server_secret, api, local_mode, backoff_mult = 10)
      super()
      unless api.end_with?('/')
        api += '/'
      end
      @server_secret = server_secret
      @api = api
      @local_mode = local_mode
      @backoff_multiplier = backoff_mult
      @session_id = SecureRandom.uuid
    end

    sig { params(endpoint: String, body: String, retries: Integer, backoff: Integer)
            .returns([T.any(HTTP::Response, NilClass), T.any(StandardError, NilClass)]) }

    def post_helper(endpoint, body, retries = 0, backoff = 1)
      if @local_mode
        return nil, nil
      end

      meta = Statsig.get_statsig_metadata
      http = HTTP.headers(
        {
          "STATSIG-API-KEY" => @server_secret,
          "STATSIG-CLIENT-TIME" => (Time.now.to_f * 1000).to_i.to_s,
          "STATSIG-SERVER-SESSION-ID" => @session_id,
          "Content-Type" => "application/json; charset=UTF-8",
          "STATSIG-SDK-TYPE" => meta['sdkType'],
          "STATSIG-SDK-VERSION" => meta['sdkVersion'],
        }).accept(:json)
      begin
        res = http.post(@api + endpoint, body: body)
      rescue StandardError => e
        ## network error retry
        return nil, e unless retries > 0
        sleep backoff
        return post_helper(endpoint, body, retries - 1, backoff * @backoff_multiplier)
      end
      return res, nil if res.status.success?
      return nil, NetworkError.new("Got an exception when making request to #{@api + endpoint}: #{res.to_s}", res.status.to_i) unless retries > 0 && $retry_codes.include?(res.code)
      ## status code retry
      sleep backoff
      post_helper(endpoint, body, retries - 1, backoff * @backoff_multiplier)
    end

    def check_gate(user, gate_name)
      begin
        request_body = JSON.generate({ 'user' => user&.serialize(false), 'gateName' => gate_name })
        response, _ = post_helper('check_gate', request_body)
        return JSON.parse(response.body) unless response.nil?
        false
      rescue
        return false
      end
    end

    def get_config(user, dynamic_config_name)
      begin
        request_body = JSON.generate({ 'user' => user&.serialize(false), 'configName' => dynamic_config_name })
        response, _ = post_helper('get_config', request_body)
        return JSON.parse(response.body) unless response.nil?
        nil
      rescue
        return nil
      end
    end

    def post_logs(events)
      begin
        json_body = JSON.generate({ 'events' => events, 'statsigMetadata' => Statsig.get_statsig_metadata })
        post_helper('log_event', json_body, 5)
      rescue
      end
    end
  end
end