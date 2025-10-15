require_relative 'constants'
require_relative 'hash_utils'

module Statsig
  class ResponseFormatter
    def self.get_responses(
      entities,
      evaluator,
      user,
      client_sdk_key,
      hash_algo,
      include_exposures: true,
      include_local_overrides: false
    )
      result = {}
      target_app_id = evaluator.spec_store.get_app_id_for_sdk_key(client_sdk_key)
      entities.each do |name, spec|
        config_target_apps = spec[:targetAppIDs]

        unless target_app_id.nil? || (!config_target_apps.nil? && config_target_apps.include?(target_app_id))
          next
        end
        hashed_name, value = to_response(name, spec, evaluator, user, client_sdk_key, hash_algo, include_exposures, include_local_overrides)
        if !hashed_name.nil? && !value.nil?
          result[hashed_name] = value
        end
      end

      result
    end

    def self.to_response(config_name, config_spec, evaluator, user, client_sdk_key, hash_algo, include_exposures, include_local_overrides)
      category = config_spec[:type]
      entity_type = config_spec[:entity]
      if entity_type == Const::TYPE_SEGMENT || entity_type == Const::TYPE_HOLDOUT
        return nil
      end

      if include_local_overrides
        case category
        when Const::TYPE_FEATURE_GATE
          local_override = evaluator.lookup_gate_override(config_name)
        when Const::TYPE_DYNAMIC_CONFIG
          local_override = evaluator.lookup_config_override(config_name)
        end
      end

      config_name_str = config_name.to_s
      if local_override.nil?
        eval_result = ConfigResult.new(
          name: config_name,
          disable_evaluation_details: true,
          disable_exposures: !include_exposures,
          include_local_overrides: include_local_overrides
        )
        evaluator.eval_spec(config_name_str, user, config_spec, eval_result)
      else
        eval_result = local_override
      end

      result = {}

      result[:id_type] = eval_result.id_type
      unless eval_result.group_name.nil?
        result[:group_name] = eval_result.group_name
      end

      case category
      when Const::TYPE_FEATURE_GATE
        result[:value] = eval_result.gate_value
      when Const::TYPE_DYNAMIC_CONFIG
        id_type = config_spec[:idType]
        result[:value] = eval_result.json_value
        result[:group] = eval_result.rule_id
        result[:is_device_based] = id_type.is_a?(String) && id_type.downcase == Statsig::Const::STABLEID
        result[:passed] = eval_result.gate_value
      else
        return nil
      end

      if entity_type == Const::TYPE_EXPERIMENT
        populate_experiment_fields(name, config_spec, eval_result, result, evaluator)
      end

      if entity_type == Const::TYPE_LAYER
        populate_layer_fields(config_spec, eval_result, result, evaluator, hash_algo, include_exposures)
        result.delete(:id_type) # not exposed for layer configs in /initialize
      end

      hashed_name = hash_name(config_name_str, hash_algo)

      result[:name] = hashed_name
      result[:rule_id] = eval_result.rule_id

      if include_exposures
        result[:secondary_exposures] = hash_exposures(eval_result.secondary_exposures, hash_algo)
      end

      [hashed_name, result]
    end

    def self.hash_exposures(exposures, hash_algo)
      return nil if exposures.nil?
      hashed_exposures = []
      exposures.each do |exp|
        hashed_exposures << {
          gate: hash_name(exp[:gate], hash_algo),
          gateValue: exp[:gateValue],
          ruleID: exp[:ruleID]
        }
      end

      hashed_exposures
    end

    def self.populate_experiment_fields(config_name, config_spec, eval_result, result, evaluator)
      result[:is_user_in_experiment] = eval_result.is_experiment_group
      result[:is_experiment_active] = config_spec[:isActive] == true

      if config_spec[:hasSharedParams] != true
        return
      end

      result[:is_in_layer] = true
      result[:explicit_parameters] = config_spec[:explicitParameters] || []
    end

    def self.populate_layer_fields(config_spec, eval_result, result, evaluator, hash_algo, include_exposures)
      delegate = eval_result.config_delegate
      result[:explicit_parameters] = config_spec[:explicitParameters] || []

      if delegate.nil? == false && delegate.empty? == false
        delegate_spec = evaluator.spec_store.configs[delegate.to_sym]

        result[:allocated_experiment_name] = hash_name(delegate, hash_algo)
        result[:is_user_in_experiment] = eval_result.is_experiment_group
        result[:is_experiment_active] = delegate_spec[:isActive] == true
        result[:explicit_parameters] = delegate_spec[:explicitParameters] || []
      end

      if include_exposures
        result[:undelegated_secondary_exposures] = hash_exposures(eval_result.undelegated_sec_exps || [], hash_algo)
      end
    end

    def self.hash_name(name, hash_algo)
      Statsig::Memo.for_global(:hash_name, "#{hash_algo}|#{name}") do
        case hash_algo
        when Statsig::Const::NONE
          name
        when Statsig::Const::DJB2
          Statsig::HashUtils.djb2(name)
        else
          Statsig::HashUtils.sha256(name)
        end
      end
    end
  end
end
