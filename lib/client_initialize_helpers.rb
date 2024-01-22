require_relative 'hash_utils'

require 'constants'

module Statsig
  class ResponseFormatter

    def self.get_responses(entities, evaluator, user, client_sdk_key, hash_algo)
      result = {}

      entities.each do |name, spec|
        hashed_name, value = to_response(name, spec, evaluator, user, client_sdk_key, hash_algo)
        if hashed_name != nil && value != nil
          result[hashed_name] = value
        end
      end

      result
    end

    def self.to_response(config_name, config_spec, evaluator, user, client_sdk_key, hash_algo)
      target_app_id = evaluator.spec_store.get_app_id_for_sdk_key(client_sdk_key)
      config_target_apps = config_spec[:targetAppIDs]

      unless target_app_id.nil? || (!config_target_apps.nil? && config_target_apps.include?(target_app_id))
        return nil
      end

      category = config_spec[:type]
      entity_type = config_spec[:entity]
      if entity_type == Statsig::Const::SEGMENT || entity_type == Statsig::Const::HOLDOUT
        return nil
      end

      eval_result = evaluator.eval_spec(user, config_spec)
      if eval_result.nil?
        return nil
      end

      result = {}

      case category

      when Statsig::Const::FEATURE_GATE
        result[:value] = eval_result.gate_value
        result[:group_name] = eval_result.group_name
        result[:id_type] = eval_result.id_type
      when Statsig::Const::DYNAMIC_CONFIG
        id_type = config_spec[:idType]
        result[:value] = eval_result.json_value
        result[:group] = eval_result.rule_id
        result[:group_name] = eval_result.group_name
        result[:id_type] = eval_result.id_type
        result[:is_device_based] = id_type.is_a?(String) && id_type.downcase == Statsig::Const::STABLEID
      else
        return nil
      end

      if entity_type == Statsig::Const::EXPERIMENT
        populate_experiment_fields(config_name, config_spec, eval_result, result, evaluator)
      end

      if entity_type == Statsig::Const::LAYER
        populate_layer_fields(config_spec, eval_result, result, evaluator, user, hash_algo)
        result.delete(:id_type) # not exposed for layer configs in /initialize
      end

      hashed_name = hash_name(config_name, hash_algo)

      result[:name] = hashed_name
      result[:rule_id] = eval_result.rule_id
      result[:secondary_exposures] = clean_exposures(eval_result.secondary_exposures)

      [hashed_name, result]
    end

    private

    def self.clean_exposures(exposures)
      seen = {}
      exposures.reject do |exposure|
        key = "#{exposure[:gate]}|#{exposure[:gateValue]}|#{exposure[:ruleID]}}"
        should_reject = seen[key]
        seen[key] = true
        should_reject == true
      end
    end

    def self.populate_experiment_fields(config_name, config_spec, eval_result, result, evaluator)
      result[:is_user_in_experiment] = eval_result.is_experiment_group
      result[:is_experiment_active] = config_spec[:isActive] == true

      if config_spec[:hasSharedParams] != true
        return
      end

      result[:is_in_layer] = true
      result[:explicit_parameters] = config_spec[:explicitParameters] || []

      layer_name = evaluator.spec_store.experiment_to_layer[config_name]
      if layer_name.nil? || evaluator.spec_store.layers[layer_name].nil?
        return
      end

      layer = evaluator.spec_store.layers[layer_name]
      result[:value] = layer[:defaultValue].merge(result[:value])
    end

    def self.populate_layer_fields(config_spec, eval_result, result, evaluator, user, hash_algo)
      delegate = eval_result.config_delegate
      result[:explicit_parameters] = config_spec[:explicitParameters] || []

      if delegate.nil? == false && delegate.empty? == false
        delegate_spec = evaluator.spec_store.configs[delegate]
        delegate_result = evaluator.eval_spec(user, delegate_spec)

        result[:allocated_experiment_name] = hash_name(delegate, hash_algo)
        result[:is_user_in_experiment] = delegate_result.is_experiment_group
        result[:is_experiment_active] = delegate_spec[:isActive] == true
        result[:explicit_parameters] = delegate_spec[:explicitParameters] || []
      end

      result[:undelegated_secondary_exposures] = clean_exposures(eval_result.undelegated_sec_exps || [])
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
