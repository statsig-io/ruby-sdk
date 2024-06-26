require_relative 'hash_utils'

require 'constants'

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
        config_target_apps = spec.target_app_ids

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
      category = config_spec.type
      entity_type = config_spec.entity
      if entity_type == :segment || entity_type == :holdout
        return nil
      end

      if include_local_overrides
        case category
        when :feature_gate
          local_override = evaluator.lookup_gate_override(config_name)
        when :dynamic_config
          local_override = evaluator.lookup_config_override(config_name)
        end
      end

      if local_override.nil?
        eval_result = ConfigResult.new(
          name: config_name,
          disable_evaluation_details: true,
          disable_exposures: !include_exposures
        )
        evaluator.eval_spec(user, config_spec, eval_result)
      else
        eval_result = local_override
      end

      result = {}

      result[:id_type] = eval_result.id_type
      unless eval_result.group_name.nil?
        result[:group_name] = eval_result.group_name
      end

      case category
      when :feature_gate
        result[:value] = eval_result.gate_value
      when :dynamic_config
        id_type = config_spec.id_type
        result[:value] = eval_result.json_value
        result[:group] = eval_result.rule_id
        result[:is_device_based] = id_type.is_a?(String) && id_type.downcase == Statsig::Const::STABLEID
      else
        return nil
      end

      if entity_type == :experiment
        populate_experiment_fields(name, config_spec, eval_result, result, evaluator)
      end

      if entity_type == :layer
        populate_layer_fields(config_spec, eval_result, result, evaluator, hash_algo, include_exposures)
        result.delete(:id_type) # not exposed for layer configs in /initialize
      end

      hashed_name = hash_name(config_name, hash_algo)

      result[:name] = hashed_name
      result[:rule_id] = eval_result.rule_id

      if include_exposures
        result[:secondary_exposures] = eval_result.secondary_exposures
      end

      [hashed_name, result]
    end

    def self.populate_experiment_fields(config_name, config_spec, eval_result, result, evaluator)
      result[:is_user_in_experiment] = eval_result.is_experiment_group
      result[:is_experiment_active] = config_spec.is_active == true

      if config_spec.has_shared_params != true
        return
      end

      result[:is_in_layer] = true
      result[:explicit_parameters] = config_spec.explicit_parameters || []

      layer_name = evaluator.spec_store.experiment_to_layer[config_name]
      if layer_name.nil? || evaluator.spec_store.layers[layer_name].nil?
        return
      end

      layer = evaluator.spec_store.layers[layer_name]
      result[:value] = layer[:defaultValue].merge(result[:value])
    end

    def self.populate_layer_fields(config_spec, eval_result, result, evaluator, hash_algo, include_exposures)
      delegate = eval_result.config_delegate
      result[:explicit_parameters] = config_spec.explicit_parameters || []

      if delegate.nil? == false && delegate.empty? == false
        delegate_spec = evaluator.spec_store.configs[delegate]

        result[:allocated_experiment_name] = hash_name(delegate, hash_algo)
        result[:is_user_in_experiment] = eval_result.is_experiment_group
        result[:is_experiment_active] = delegate_spec.is_active == true
        result[:explicit_parameters] = delegate_spec.explicit_parameters || []
      end

      if include_exposures
        result[:undelegated_secondary_exposures] = eval_result.undelegated_sec_exps || []
      end
    end

    def self.hash_name(name, hash_algo)
      case hash_algo
      when Statsig::Const::NONE
        return name
      when Statsig::Const::DJB2
        return Statsig::HashUtils.djb2(name)
      else
        return Statsig::HashUtils.sha256(name)
      end
    end
  end
end
