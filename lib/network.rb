require 'http'
require 'json'
require 'dynamic_config'

class Network
  def initialize(server_secret, api)
    super()
    unless api.end_with?('/')
      api += '/'
    end
    @http = HTTP
        .headers({"STATSIG-API-KEY" => server_secret, "Content-Type" => "application/json; charset=UTF-8"})
        .accept(:json)
    @api = api
    @last_sync_time = 0
  end

  def check_gate(user, gate_name)
    begin
      request_body = JSON.generate({'user' => user&.serialize(), 'gateName' => gate_name})
      response = @http.post(@api + 'check_gate', body: request_body)
      return JSON.parse(response.body)
    rescue
      return false
    end
  end

  def get_config(user, dynamic_config_name)
    begin
      request_body = JSON.generate({'user' => user&.serialize(), 'configName' => dynamic_config_name})
      response = @http.post(@api + 'get_config', body: request_body)
      return JSON.parse(response.body)
    rescue
      return nil
    end
  end

  def download_config_specs
    begin
      response = @http.post(@api + 'download_config_specs', body: JSON.generate({'sinceTime' => @last_sync_time}))
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
      @http.post(@api + 'log_event', body: json_body)
    rescue
      # TODO: retries
    end
  end
end