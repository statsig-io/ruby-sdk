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
    attr_accessor :group_name
    attr_accessor :id_type
    attr_accessor :target_app_ids
    attr_accessor :disable_evaluation_details
    attr_accessor :disable_exposures
    attr_accessor :config_version
    attr_accessor :include_local_overrides
    attr_accessor :forward_all_exposures
    attr_accessor :sampling_rate
    attr_accessor :has_seen_analytical_gates
    attr_accessor :override_config_name

    def initialize(
      name:,
      gate_value: false,
      json_value: nil,
      rule_id: nil,
      secondary_exposures: [],
      config_delegate: nil,
      explicit_parameters: nil,
      is_experiment_group: false,
      evaluation_details: nil,
      group_name: nil,
      id_type: nil,
      target_app_ids: nil,
      disable_evaluation_details: false,
      disable_exposures: false,
      config_version: nil,
      include_local_overrides: true,
      forward_all_exposures: false,
      sampling_rate: nil,
      has_seen_analytical_gates: false,
      override_config_name: nil
    )
      @name = name
      @gate_value = gate_value
      @json_value = json_value
      @rule_id = rule_id
      @secondary_exposures = secondary_exposures
      @undelegated_sec_exps = @secondary_exposures
      @config_delegate = config_delegate
      @explicit_parameters = explicit_parameters
      @is_experiment_group = is_experiment_group
      @evaluation_details = evaluation_details
      @group_name = group_name
      @id_type = id_type
      @target_app_ids = target_app_ids
      @disable_evaluation_details = disable_evaluation_details
      @disable_exposures = disable_exposures
      @config_version = config_version
      @include_local_overrides = include_local_overrides
      @forward_all_exposures = forward_all_exposures
      @sampling_rate = sampling_rate
      @has_seen_analytical_gates = has_seen_analytical_gates
      @override_config_name = override_config_name
    end

    def self.from_user_persisted_values(config_name, user_persisted_values)
      sticky_values = user_persisted_values[config_name]
      return nil if sticky_values.nil?

      from_hash(config_name, sticky_values)
    end

    def to_hash
      {
        json_value: @json_value,
        gate_value: @gate_value,
        rule_id: @rule_id,
        secondary_exposures: @secondary_exposures,
        config_sync_time: @evaluation_details.config_sync_time,
        init_time: @init_time,
        group_name: @group_name,
        id_type: @id_type,
        target_app_ids: @target_app_ids,
        override_config_name: @override_config_name
      }
    end
  end
end
