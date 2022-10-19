module Statsig
  class ConfigResult
    attr_accessor :name
    attr_accessor :gate_value
    attr_accessor :json_value
    attr_accessor :rule_id
    attr_accessor :secondary_exposures
    attr_accessor :undelegated_sec_exps
    attr_accessor :config_delegate
    attr_accessor :explicit_parameters
    attr_accessor :is_experiment_group
    attr_accessor :evaluation_details

    def initialize(
      name,
      gate_value = false,
      json_value = {},
      rule_id = '',
      secondary_exposures = [],
      config_delegate = '',
      explicit_parameters = [],
      is_experiment_group: false,
      evaluation_details: nil)
      @name = name
      @gate_value = gate_value
      @json_value = json_value
      @rule_id = rule_id
      @secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []
      @undelegated_sec_exps = @secondary_exposures
      @config_delegate = config_delegate
      @explicit_parameters = explicit_parameters
      @is_experiment_group = is_experiment_group
      @evaluation_details = evaluation_details
    end
  end
end