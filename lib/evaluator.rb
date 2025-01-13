require 'config_result'
require 'country_lookup'
require 'digest'
require 'evaluation_helpers'
require 'client_initialize_helpers'
require 'spec_store'
require 'time'
require 'ua_parser'
require 'evaluation_details'
require 'user_agent_parser/operating_system'
require 'user_persistent_storage_utils'
require 'constants'

module Statsig
  class Evaluator

    attr_accessor :spec_store

    attr_accessor :gate_overrides

    attr_accessor :config_overrides

    attr_accessor :options

    attr_accessor :persistent_storage_utils

    def initialize(store, options, persistent_storage_utils)
      UAParser.initialize_async
      CountryLookup.initialize_async

      @spec_store = store
      @gate_overrides = {}
      @config_overrides = {}
      @options = options
      @persistent_storage_utils = persistent_storage_utils
    end

    def maybe_restart_background_threads
      @spec_store.maybe_restart_background_threads
    end

    def lookup_gate_override(gate_name)
      gate_name_sym = gate_name.to_sym
      if @gate_overrides.key?(gate_name_sym)
        return ConfigResult.new(
          name: gate_name,
          gate_value: @gate_overrides[gate_name_sym],
          rule_id: Const::OVERRIDE,
          id_type: @spec_store.has_gate?(gate_name) ? @spec_store.get_gate(gate_name)[:idType] : Const::EMPTY_STR,
          evaluation_details: EvaluationDetails.local_override(
            @spec_store.last_config_sync_time,
            @spec_store.initial_config_sync_time
          )
        )
      end
      return nil
    end

    def lookup_config_override(config_name)
      config_name_sym = config_name.to_sym
      if @config_overrides.key?(config_name_sym)
        return ConfigResult.new(
          name: config_name,
          json_value: @config_overrides[config_name_sym],
          rule_id: Const::OVERRIDE,
          id_type: @spec_store.has_config?(config_name) ? @spec_store.get_config(config_name)[:idType] : Const::EMPTY_STR,
          evaluation_details: EvaluationDetails.local_override(
            @spec_store.last_config_sync_time,
            @spec_store.initial_config_sync_time
          )
        )
      end
      return nil
    end

    def check_gate(user, gate_name, end_result, ignore_local_overrides: false, is_nested: false)
      unless ignore_local_overrides
        local_override = lookup_gate_override(gate_name)
        unless local_override.nil?
          end_result.gate_value = local_override.gate_value
          end_result.rule_id = local_override.rule_id
          unless end_result.disable_evaluation_details
            end_result.evaluation_details = local_override.evaluation_details
          end
          return
        end
      end

      if @spec_store.init_reason == EvaluationReason::UNINITIALIZED
        unless end_result.disable_evaluation_details
          end_result.evaluation_details = EvaluationDetails.uninitialized
        end
        return
      end

      unless @spec_store.has_gate?(gate_name)
        unsupported_or_unrecognized(gate_name, end_result)
        return
      end

      eval_spec(gate_name, user, @spec_store.get_gate(gate_name), end_result, is_nested: is_nested)
    end

    def get_config(user, config_name, end_result, user_persisted_values: nil, ignore_local_overrides: false)
      unless ignore_local_overrides
        local_override = lookup_config_override(config_name)
        unless local_override.nil?
          end_result.id_type = local_override.id_type
          end_result.rule_id = local_override.rule_id
          end_result.json_value = local_override.json_value
          unless end_result.disable_evaluation_details
            end_result.evaluation_details = local_override.evaluation_details
          end
          return
        end
      end

      if @spec_store.init_reason == EvaluationReason::UNINITIALIZED
        unless end_result.disable_evaluation_details
          end_result.evaluation_details = EvaluationDetails.uninitialized
        end
        return
      end

      unless @spec_store.has_config?(config_name)
        unsupported_or_unrecognized(config_name, end_result)
        return
      end

      config = @spec_store.get_config(config_name)

      # If persisted values is provided and the experiment is active, return sticky values if exists.
      if !user_persisted_values.nil? && config[:isActive] == true
        sticky_values = user_persisted_values[config_name]
        unless sticky_values.nil?
          end_result.gate_value = sticky_values[Statsig::Const::GATE_VALUE]
          end_result.json_value = sticky_values[Statsig::Const::JSON_VALUE]
          end_result.rule_id = sticky_values[Statsig::Const::RULE_ID]
          end_result.secondary_exposures = sticky_values[Statsig::Const::SECONDARY_EXPOSURES]
          end_result.group_name = sticky_values[Statsig::Const::GROUP_NAME]
          end_result.id_type = sticky_values[Statsig::Const::ID_TYPE]
          end_result.target_app_ids = sticky_values[Statsig::Const::TARGET_APP_IDS]
          unless end_result.disable_evaluation_details
            end_result.evaluation_details = EvaluationDetails.persisted(
              sticky_values[Statsig::Const::CONFIG_SYNC_TIME],
              sticky_values[Statsig::Const::INIT_TIME]
            )
          end
          return
        end

        # If it doesn't exist, then save to persisted storage if the user was assigned to an experiment group.
        eval_spec(config_name, user, config, end_result)
        if end_result.is_experiment_group
          @persistent_storage_utils.add_evaluation_to_user_persisted_values(user_persisted_values, config_name,
                                                                            end_result)
          @persistent_storage_utils.save_to_storage(user, config[:idType], user_persisted_values)
        end
        # Otherwise, remove from persisted storage
      else
        @persistent_storage_utils.remove_experiment_from_storage(user, config[:idType], config_name)
        eval_spec(config_name, user, config, end_result)
      end
    end

    def get_layer(user, layer_name, end_result)
      if @spec_store.init_reason == EvaluationReason::UNINITIALIZED
        unless end_result.disable_evaluation_details
          end_result.evaluation_details = EvaluationDetails.uninitialized
        end
        return
      end

      unless @spec_store.has_layer?(layer_name)
        unsupported_or_unrecognized(layer_name, end_result)
        return
      end

      eval_spec(layer_name, user, @spec_store.get_layer(layer_name), end_result)
    end

    def list_gates
      @spec_store.gates.keys.map(&:to_s)
    end

    def list_configs
      keys = []
      @spec_store.configs.each do |key, value|
        if value[:entity] == Const::TYPE_DYNAMIC_CONFIG
          keys << key.to_s
        end
      end
      keys
    end

    def list_experiments
      keys = []
      @spec_store.configs.each do |key, value|
        if value[:entity] == Const::TYPE_EXPERIMENT
          keys << key.to_s
        end
      end
      keys
    end

    def list_autotunes
      keys = []
      @spec_store.configs.each do |key, value|
        if value[:entity] == Const::TYPE_AUTOTUNE
          keys << key.to_s
        end
      end
      keys    end

    def list_layers
      @spec_store.layers.keys.map(&:to_s)
    end

    def get_client_initialize_response(user, hash_algo, client_sdk_key, include_local_overrides)
      if @spec_store.is_ready_for_checks == false
        return nil
      end
      if @spec_store.last_config_sync_time == 0
        return nil
      end

      evaluated_keys = {}
      if user.user_id.nil? == false
        evaluated_keys[:userID] = user.user_id
      end

      if user.custom_ids.nil? == false
        evaluated_keys[:customIDs] = user.custom_ids
      end
      meta = Statsig.get_statsig_metadata
      {
        feature_gates: Statsig::ResponseFormatter
                         .get_responses(@spec_store.gates, self, user, client_sdk_key, hash_algo, include_local_overrides: include_local_overrides),
        dynamic_configs: Statsig::ResponseFormatter
                           .get_responses(@spec_store.configs, self, user, client_sdk_key, hash_algo, include_local_overrides: include_local_overrides),
        layer_configs: Statsig::ResponseFormatter
                         .get_responses(@spec_store.layers, self, user, client_sdk_key, hash_algo, include_local_overrides: include_local_overrides),
        sdkParams: {},
        has_updates: true,
        generator: Const::STATSIG_RUBY_SDK,
        evaluated_keys: evaluated_keys,
        time: @spec_store.last_config_sync_time,
        hash_used: hash_algo,
        user: user.serialize(true),
        sdkInfo: {sdkType: meta["sdkType"], sdkVersion: meta["sdkVersion"]},
      }
    end

    def shutdown
      @spec_store.shutdown
    end

    def unsupported_or_unrecognized(config_name, end_result)
      end_result.rule_id = Const::EMPTY_STR

      if end_result.disable_evaluation_details
        return
      end

      if @spec_store.unsupported_configs.include?(config_name)
        end_result.evaluation_details = EvaluationDetails.unsupported(
          @spec_store.last_config_sync_time,
          @spec_store.initial_config_sync_time
        )
        return
      end

      end_result.evaluation_details = EvaluationDetails.unrecognized(
        @spec_store.last_config_sync_time,
        @spec_store.initial_config_sync_time
      )
    end

    def override_gate(gate, value)
      @gate_overrides[gate.to_sym] = value
    end

    def remove_gate_override(gate)
      @gate_overrides.delete(gate.to_sym)
    end

    def clear_gate_overrides
      @gate_overrides.clear
    end

    def override_config(config, value)
      @config_overrides[config.to_sym] = value
    end

    def remove_config_override(config)
      @config_overrides.delete(config.to_sym)
    end

    def clear_config_overrides
      @config_overrides.clear
    end

    def eval_spec(config_name, user, config, end_result, is_nested: false)
      config[:rules].each do |rule|
        eval_rule(user, rule, end_result)

        if end_result.gate_value
          if eval_delegate(config_name, user, rule, end_result)
            finalize_secondary_exposures(end_result)
            return
          end

          pass = eval_pass_percent(user, rule, config[:salt])
          finalize_eval_result(config, end_result, did_pass: pass, rule: rule, is_nested: is_nested)
          return
        end
      end

      finalize_eval_result(config, end_result, did_pass: false, rule: nil, is_nested: is_nested)
    end

    private

    def finalize_eval_result(config, end_result, did_pass:, rule:, is_nested: false)
      end_result.id_type = config[:idType]
      end_result.target_app_ids = config[:targetAppIDs]
      end_result.gate_value = did_pass
      if config[:entity] == Const::TYPE_FEATURE_GATE
        end_result.gate_value = did_pass ? rule[:returnValue] == true : config[:defaultValue] == true
      end
      end_result.config_version = config[:version]

      if rule.nil?
        end_result.json_value = config[:defaultValue]
        end_result.group_name = nil
        end_result.is_experiment_group = false
        end_result.rule_id = config[:enabled] ? Const::DEFAULT : Const::DISABLED
      else
        end_result.json_value = did_pass ? rule[:returnValue] : config[:defaultValue]
        end_result.group_name = rule[:groupName]
        end_result.is_experiment_group = rule[:isExperimentGroup] == true
        end_result.rule_id = rule[:id]
      end

      unless end_result.disable_evaluation_details
        end_result.evaluation_details = EvaluationDetails.new(
          @spec_store.last_config_sync_time,
          @spec_store.initial_config_sync_time,
          @spec_store.init_reason
        )
      end

      unless is_nested
        finalize_secondary_exposures(end_result)
      end
    end

    def finalize_secondary_exposures(end_result)
      end_result.secondary_exposures = clean_exposures(end_result.secondary_exposures)
      end_result.undelegated_sec_exps = clean_exposures(end_result.undelegated_sec_exps)
    end

    def clean_exposures(exposures)
      seen = {}
      exposures.reject do |exposure|
        if exposure[:gate].to_s.start_with?(Const::SEGMENT_PREFIX)
          should_reject = true
        else
          key = "#{exposure[:gate]}|#{exposure[:gateValue]}|#{exposure[:ruleID]}}"
          should_reject = seen[key]
          seen[key] = true
        end
        should_reject == true
      end
    end

    def eval_rule(user, rule, end_result)
      pass = true
      i = 0

      until i >= rule[:conditions].length
        condition_hash = rule[:conditions][i]
        condition = @spec_store.get_condition(condition_hash)

        if condition.nil?
          puts "[Statsig]: Warning - Condition with hash #{condition_hash} could not be found."
          pass = false
        else
          result = eval_condition(user, condition, end_result)
          pass = false if result != true
        end

        i += 1
      end

      end_result.gate_value = pass
    end

    def eval_delegate(name, user, rule, end_result)
      return false unless (delegate = rule[:configDelegate])
      return false unless (delegate_config = @spec_store.get_config(delegate))

      end_result.undelegated_sec_exps = end_result.secondary_exposures.dup

      eval_spec(delegate, user, delegate_config, end_result, is_nested: true)

      end_result.name = name
      end_result.config_delegate = delegate
      end_result.explicit_parameters = delegate_config[:explicitParameters]

      true
    end

    def eval_condition(user, condition, end_result)
      value = nil
      field = condition[:field]
      target = condition[:targetValue]
      type = condition[:type]
      operator = condition[:operator]
      additional_values = condition[:additionalValues]
      id_type = condition[:idType]

      case type
      when Const::CND_PUBLIC
        return true
      when Const::CND_PASS_GATE, Const::CND_FAIL_GATE
        result = eval_nested_gate(target, user, end_result)
        return type == Const::CND_PASS_GATE ? result : !result
      when Const::CND_MULTI_PASS_GATE, Const::CND_MULTI_FAIL_GATE
        return eval_nested_gates(target, type, user, end_result)
      when Const::CND_IP_BASED
        value = get_value_from_user(user, field) || get_value_from_ip(user, field)
      when Const::CND_UA_BASED
        value = get_value_from_user(user, field) || get_value_from_ua(user, field)
      when Const::CND_USER_FIELD
        value = get_value_from_user(user, field)
      when Const::CND_ENVIRONMENT_FIELD
        value = get_value_from_environment(user, field)
      when Const::CND_CURRENT_TIME
        value = Time.now.to_i # epoch time in seconds
      when Const::CND_USER_BUCKET
        begin
          salt = additional_values[:salt]
          unit_id = user.get_unit_id(id_type) || Const::EMPTY_STR
          # there are only 1000 user buckets as opposed to 10k for gate pass %
          value = (compute_user_hash("#{salt}.#{unit_id}") % 1000).to_s
        rescue StandardError
          return false
        end
      when Const::CND_UNIT_ID
        value = user.get_unit_id(id_type)
      end

      case operator
        # numerical comparison
      when Const::OP_GREATER_THAN
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a > b })
      when Const::OP_GREATER_THAN_OR_EQUAL
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a >= b })
      when Const::OP_LESS_THAN
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a < b })
      when Const::OP_LESS_THAN_OR_EQUAL
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a <= b })

        # version comparison
        # need to check for nil or empty value because Version takes them as valid values
      when Const::OP_VERSION_GREATER_THAN
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) > Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when Const::OP_VERSION_GREATER_THAN_OR_EQUAL
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) >= Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when Const::OP_VERSION_LESS_THAN
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) < Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when Const::OP_VERSION_LESS_THAN_OR_EQUAL
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) <= Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when Const::OP_VERSION_EQUAL
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) == Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when Const::OP_VERSION_NOT_EQUAL
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) != Gem::Version.new(target)
               rescue StandardError
                 false
               end

        # array operations
      when Const::OP_ANY
        return EvaluationHelpers::equal_string_in_array(target, value, true)
      when Const::OP_NONE
        return !EvaluationHelpers::equal_string_in_array(target, value, true)
      when Const::OP_ANY_CASE_SENSITIVE
        return EvaluationHelpers::equal_string_in_array(target, value, false)
      when Const::OP_NONE_CASE_SENSITIVE
        return !EvaluationHelpers::equal_string_in_array(target, value, false)

        # string
      when Const::OP_STR_STARTS_WITH_ANY
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.start_with?(b) })
      when Const::OP_STR_END_WITH_ANY
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.end_with?(b) })
      when Const::OP_STR_CONTAINS_ANY
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.include?(b) })
      when Const::OP_STR_CONTAINS_NONE
        return !EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.include?(b) })
      when Const::OP_STR_MATCHES
        return begin
                 value&.is_a?(String) && !(value =~ Regexp.new(target)).nil?
               rescue StandardError
                 false
               end
      when Const::OP_EQUAL
        return value == target
      when Const::OP_NOT_EQUAL
        return value != target

        # dates
      when Const::OP_BEFORE
        return EvaluationHelpers.compare_times(value, target, ->(a, b) { a < b })
      when Const::OP_AFTER
        return EvaluationHelpers.compare_times(value, target, ->(a, b) { a > b })
      when Const::OP_ON
        return EvaluationHelpers.compare_times(value, target, lambda { |a, b|
          a.year == b.year && a.month == b.month && a.day == b.day
        })

        # array
      when Const::OP_ARRAY_CONTAINS_ANY
        if value.is_a?(Array) && target.is_a?(Array)
          return EvaluationHelpers.array_contains_any(value, target)
        end
      when Const::OP_ARRAY_CONTAINS_NONE
        if value.is_a?(Array) && target.is_a?(Array)
          return !EvaluationHelpers.array_contains_any(value, target)
        end
      when Const::OP_ARRAY_CONTAINS_ALL
        if value.is_a?(Array) && target.is_a?(Array)
          return EvaluationHelpers.array_contains_all(value, target)
        end
      when Const::OP_NOT_ARRAY_CONTAINS_ALL
        if value.is_a?(Array) && target.is_a?(Array)
          return !EvaluationHelpers.array_contains_all(value, target)
        end

        # segments
      when Const::OP_IN_SEGMENT_LIST, Const::OP_NOT_IN_SEGMENT_LIST
        begin
          is_in_list = false
          id_list = @spec_store.get_id_list(target)
          if id_list.is_a? IDList
            hashed_id = Digest::SHA256.base64digest(value.to_s)[0, 8]
            is_in_list = id_list.ids.include?(hashed_id)
          end
          return is_in_list if operator == Const::OP_IN_SEGMENT_LIST

          return !is_in_list
        rescue StandardError
          return false
        end
      end
      return false
    end

    def eval_nested_gate(gate_name, user, end_result)
      check_gate(user, gate_name, end_result, is_nested: true,
                                              ignore_local_overrides: !end_result.include_local_overrides)
      gate_value = end_result.gate_value

      unless end_result.disable_exposures
        new_exposure = {
          gate: gate_name,
          gateValue: gate_value ? Const::TRUE : Const::FALSE,
          ruleID: end_result.rule_id
        }
        end_result.secondary_exposures.append(new_exposure)
      end

      gate_value
    end

    def eval_nested_gates(gate_names, condition_type, user, end_result)
      has_passing_gate = false
      is_multi_pass_gate_type = condition_type == Const::CND_MULTI_PASS_GATE
      gate_names.each { |gate_name|
        result = eval_nested_gate(gate_name, user, end_result)

        if is_multi_pass_gate_type == result
          has_passing_gate = true
          break
        end
      }

      has_passing_gate
    end

    def get_value_from_user(user, field)
      return nil unless field.is_a?(String)

      value = get_value_from_user_field(user, field.downcase)

      if value.nil?
        value = user.custom[field] if user.custom.is_a?(Hash)
        value = user.custom[field.to_sym] if value.nil? && user.custom.is_a?(Hash)
        value = user.private_attributes[field] if value.nil? && user.private_attributes.is_a?(Hash)
        value = user.private_attributes[field.to_sym] if value.nil? && user.private_attributes.is_a?(Hash)
      end
      value
    end

    def get_value_from_user_field(user, field)
      return nil unless field.is_a?(String)

      case field
      when Const::USERID, Const::USER_ID
        user.user_id
      when Const::EMAIL
        user.email
      when Const::IP
        user.ip
      when Const::USERAGENT, Const::USER_AGENT
        user.user_agent
      when Const::COUNTRY
        user.country
      when Const::LOCALE
        user.locale
      when Const::APPVERSION, Const::APP_VERSION
        user.app_version
      else
        nil
      end
    end

    def get_value_from_environment(user, field)
      return nil unless user.statsig_environment.is_a?(Hash) && field.is_a?(String)

      user.statsig_environment.each do |key, value|
        return value if key.to_s.downcase == (field)
      end
      nil
    end

    def get_value_from_ip(user, field)
      return nil unless field == Const::COUNTRY

      ip = get_value_from_user(user, Const::IP)
      return nil unless ip.is_a?(String)

      CountryLookup.lookup_ip_string(ip)
    end

    def get_value_from_ua(user, field)
      return nil unless field.is_a?(String)

      ua = get_value_from_user(user, Const::USER_AGENT)

      return nil unless ua.is_a?(String)
      case field.downcase
      when Const::OSNAME, Const::OS_NAME
        os = UAParser.parse_os(ua)
        return os&.family
      when Const::OS_VERSION, Const::OSVERSION
        os = UAParser.parse_os(ua)
        return os&.version unless os&.version.nil?
      when Const::BROWSERNAME, Const::BROWSER_NAME
        parsed = UAParser.parse_ua(ua)
        return parsed.family
      when Const::BROWSERVERSION, Const::BROWSER_VERSION
        parsed = UAParser.parse_ua(ua)
        return parsed.version.to_s
      end
    end

    def eval_pass_percent(user, rule, config_salt)
      pass_percentage = rule[:passPercentage]
      return true if pass_percentage == 100.0
      return false if pass_percentage == 0.0

      unit_id = user.get_unit_id(rule[:idType]) || Const::EMPTY_STR
      rule_salt = rule[:salt] || rule[:id] || Const::EMPTY_STR
      hash = compute_user_hash("#{config_salt}.#{rule_salt}.#{unit_id}")
      return (hash % 10_000) < (pass_percentage * 100)
    end

    def compute_user_hash(user_hash)
      Digest::SHA256.digest(user_hash).unpack1(Const::Q_RIGHT_CHEVRON)
    end

  end
end
