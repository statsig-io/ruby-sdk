require 'http'
require 'json'
require 'dynamic_config'

$retry_codes = [408, 500, 502, 503, 504, 522, 524, 599]

module Statsig
  class Network
    def initialize(server_secret, api, backoff_mult = 10)
      super()
      unless api.end_with?('/')
        api += '/'
      end
      @server_secret = server_secret
      @api = api
      @backoff_multiplier = backoff_mult
    end

    def post_helper(endpoint, body, retries = 0, backoff = 1)
      http = HTTP.headers(
        {"STATSIG-API-KEY" => @server_secret,
        "STATSIG-CLIENT-TIME" => (Time.now.to_f * 1000).to_s,
        "Content-Type" => "application/json; charset=UTF-8"
        }).accept(:json)
      begin
        res = http.post(@api + endpoint, body: body)
      rescue StandardError => e
        ## network error retry
        return nil, e unless retries > 0
        sleep backoff
        return post_helper(endpoint, body, retries - 1, backoff * @backoff_multiplier)
      end
      return res, nil unless !res.status.success?
      return nil, StandardError.new("Got an exception when making request to #{@api + endpoint}: #{res.to_s}") unless retries > 0 && $retry_codes.include?(res.code)
      ## status code retry
      sleep backoff
      post_helper(endpoint, body, retries - 1, backoff * @backoff_multiplier)
    end

    def check_gate(user, gate_name)
      begin
        request_body = JSON.generate({'user' => user&.serialize(false), 'gateName' => gate_name})
        response, _ = post_helper('check_gate', request_body)
        return JSON.parse(response.body) unless response.nil?
        false
      rescue
        return false
      end
    end

    def get_config(user, dynamic_config_name)
      begin
        request_body = JSON.generate({'user' => user&.serialize(false), 'configName' => dynamic_config_name})
        response, _ = post_helper('get_config', request_body)
        return JSON.parse(response.body) unless response.nil?
        nil
      rescue
        return nil
      end
    end

    def post_logs(events)
      begin
        json_body = JSON.generate({'events' => events, 'statsigMetadata' => Statsig.get_statsig_metadata})
        post_helper('log_event', json_body, retries: 5)
      rescue
      end
    end
  end
end