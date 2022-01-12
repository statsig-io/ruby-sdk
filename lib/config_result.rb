
module Statsig
  class ConfigResult
    attr_accessor :name
    attr_accessor :gate_value
    attr_accessor :json_value
    attr_accessor :rule_id
    attr_accessor :secondary_exposures

    def initialize(name, gate_value = false, json_value = {}, rule_id = '', secondary_exposures = [])
      @name = name
      @gate_value = gate_value
      @json_value = json_value
      @rule_id = rule_id
      @secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []
    end
  end
end