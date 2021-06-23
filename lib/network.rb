require 'http'
require 'json'
require 'dynamic_config'

class Network
  def initialize(server_secret, api)
    super()
    unless api.end_with?('/')
      api += '/'
    end
    @server_secret = server_secret
    @api = api
    @last_sync_time = 0
  end

  def post_helper(endpoint, body)
    http = HTTP.headers(
      {"STATSIG-API-KEY" => @server_secret,
       "STATSIG-CLIENT-TIME" => (Time.now.to_f * 1000).to_s,
       "Content-Type" => "application/json; charset=UTF-8"
      }).accept(:json)
    http.post(@api + endpoint, body: body)
  end

  def check_gate(user, gate_name)
    begin
      request_body = JSON.generate({'user' => user&.serialize, 'gateName' => gate_name})
      response = post_helper('check_gate', request_body)
      return JSON.parse(response.body)
    rescue
      return false
    end
  end

  def get_config(user, dynamic_config_name)
    begin
      request_body = JSON.generate({'user' => user&.serialize, 'configName' => dynamic_config_name})
      response = post_helper('get_config', request_body)
      return JSON.parse(response.body)
    rescue
      return nil
    end
  end

  def download_config_specs
    begin
      response = post_helper('download_config_specs', JSON.generate({'sinceTime' => @last_sync_time}))
      json_body = JSON.parse(response.body)
      @last_sync_time = json_body['time']
      return json_body
    rescue
      return nil
    end
  end

  def poll_for_changes(callback)
    Thread.new do
      loop do
        sleep 10
        specs = download_config_specs
        unless specs.nil?
          callback.call(specs)
        end
      end
    end
  end

  def post_logs(events, statsig_metadata)
    begin
      json_body = JSON.generate({'events' => events, 'statsigMetadata' => statsig_metadata})
      post_helper('log_event', body: json_body)
    rescue
      # TODO: retries
    end
  end
end