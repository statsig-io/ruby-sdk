require 'concurrent'
require 'http'
require 'json'
require 'dynamic_config'

class Network
  include Concurrent::Async

  # TODO: JSON Exception Catching

  def initialize(server_secret, api)
    super()
    if !api.end_with?('/')
      api += '/'
    end
    @http = HTTP
        .headers({"STATSIG-API-KEY" => server_secret, "Content-Type" => "application/json; charset=UTF-8"})
        .accept(:json)
    @api = api
  end

  def check_gate(user, gate_name)
    request_body = JSON.generate({'user' => user&.serialize(), 'gateName' => gate_name})
    response = @http.post(@api + 'check_gate', body: request_body)
    gate = JSON.parse(response.body)
    puts gate
    return false if gate.nil? || gate['value'].nil?
    gate['value']
  end

  def get_config(user, dynamic_config_name)
    request_body = JSON.generate({'user' => user&.serialize(), 'configName' => dynamic_config_name})
    response = @http.post(@api + 'get_config', body: request_body)
    config = JSON.parse(response.body)
    puts config
    return DynamicConfig.new({}) if config.nil? || config['value'].nil?
    DynamicConfig.new(config)
  end

  def download_config_specs
    # TODO: polling
    response = @http.post(@api + 'download_config_specs', body: JSON.generate({}))
    puts response
    return JSON.parse(response.body)
  end

  def post_logs(events, statsigMetadata)
    json_body = JSON.generate({'events' => events, 'statsigMetadata' => statsigMetadata})
    @http.post(@api + 'log_event', body: json_body)
    ## TODO: retries
  end
end