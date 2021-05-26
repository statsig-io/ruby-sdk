require 'net/http'
require 'uri'

class SpecStore
  attr_reader :store
  def initialize(api_url_base, server_secret)
    @initialized = false
    @api_url_base = api_url_base || 'https://api.statsig.com/v1'
    @server_secret = server_secret
    @last_sync_time = 0
    @store = { :gates => {}, :configs => {} }
    @sync_interval = 10

    # TODO - network request
    specs_json_string = '' # TODO - fix
    specs_json = JSON.parse(specs_json_string, object_class: OpenStruct)
    self.process(specs_json)
  end

  def sync_values
    # TODO: fetch values and sync every 10 sec
  end

  def shutdown
    # TODO
    print(@api_url_base)
  end

  private

  def process(specs_json)
    @last_sync_time = specs_json['time'] || @last_sync_time
    return unless specs_json['has_updates'] == true &&
      !specs_json['feature_gates'].nil? &&
      !specs_json['dynamic_configs'].nil?

    @store[:gates] = specs_json['feature_gates']
    @store[:configs] = specs_json['dynamic_configs']
  end
end
