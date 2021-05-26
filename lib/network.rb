require 'concurrent'
require 'http'
require 'json'
require 'dynamic_config'

class Network
  include Concurrent::Async

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

  def check_gate(gate_name)
    response =  @http.post(@api + 'check_gate', body: JSON.generate({'gateName' => gate_name}))
    gate = JSON.parse(response.body)
    puts gate
    return false if gate.nil? || gate['value'].nil?
    gate['value']
  end

  def get_config(dyanmic_config_name)
    response =  @http.post(@api + 'get_config', body: JSON.generate({'configName' => dyanmic_config_name}))
    config = JSON.parse(response.body)
    puts config
    return DynamicConfig.new({}) if config.nil? || config['value'].nil?
    DynamicConfig.new(config)
  end

  def download_config_specs
    response =  @http.post(@api + 'download_config_specs', body: JSON.generate({}))
    puts response
    return JSON.parse(response.body)
  end
end