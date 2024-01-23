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

    def initialize(
      name,
      gate_value = false,
      json_value = {},
      rule_id = '',
      secondary_exposures = [],
      config_delegate = nil,
      explicit_parameters = [],
      is_experiment_group: false,
      evaluation_details: nil,
      group_name: nil,
      id_type: '',
      target_app_ids: nil,
      disable_evaluation_details: false)
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
      @group_name = group_name
      @id_type = id_type
      @target_app_ids = target_app_ids
      @disable_evaluation_details = disable_evaluation_details
    end

    def self.from_user_persisted_values(config_name, user_persisted_values)
      sticky_values = user_persisted_values[config_name]
      return nil if sticky_values.nil?

      from_hash(config_name, sticky_values)
    end

    def self.from_hash(config_name, hash)
      new(
        config_name,
        hash['gate_value'],
        hash['json_value'],
        hash['rule_id'],
        hash['secondary_exposures'],
        evaluation_details: EvaluationDetails.persisted(hash['config_sync_time'], hash['init_time']),
        group_name: hash['group_name'],
        id_type: hash['id_type'],
        target_app_ids: hash['target_app_ids']
      )
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
        target_app_ids: @target_app_ids
      }
    end
  end
end
