
module Statsig
  class ConfigResult
    attr_accessor :name
    attr_accessor :gate_value
    attr_accessor :json_value
    attr_accessor :rule_id
    attr_accessor :secondary_exposures
    attr_accessor :undelegated_sec_exps
    attr_accessor :config_delegate

    def initialize(name, gate_value = false, json_value = {}, rule_id = '', secondary_exposures = [], undelegated_sec_exps = [], config_delegate = '')
      @name = name
      @gate_value = gate_value
      @json_value = json_value
      @rule_id = rule_id
      @secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []
      @undelegated_sec_exps = undelegated_sec_exps.is_a?(Array) ? undelegated_sec_exps : []
      @config_delegate = config_delegate
    end
  end
end