require 'net/http'
require 'uri'

class SpecStore
  def initialize(specs_json)
    @last_sync_time = 0
    @store = {
      :gates => {},
      :configs => {},
    }
    process(specs_json)
  end

  def process(specs_json)
    @last_sync_time = specs_json['time'] || @last_sync_time
    return unless specs_json['has_updates'] == true &&
      !specs_json['feature_gates'].nil? &&
      !specs_json['dynamic_configs'].nil?

    @store = {
      :gates => {},
      :configs => {},
    }

    specs_json['feature_gates'].map{|gate|  @store[:gates][gate['name']] = gate }
    specs_json['dynamic_configs'].map{|config|  @store[:configs][config['name']] = config }
  end

  def has_gate?(gate_name)
    return @store[:gates].key?(gate_name)
  end

  def has_config?(config_name)
    return @store[:configs].key?(config_name)
  end

  def get_gate(gate_name)
    return nil unless has_gate?(gate_name)
    @store[:gates][gate_name]
  end

  def get_config(config_name)
    return nil unless has_config?(config_name)
    @store[:configs][config_name]
  end

end
