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
      if @gate_overrides.key?(gate_name)
        return ConfigResult.new(
          name: gate_name,
          gate_value: @gate_overrides[gate_name],
          rule_id: Const::OVERRIDE,
          id_type: @spec_store.has_gate?(gate_name) ? @spec_store.get_gate(gate_name).id_type : Const::EMPTY_STR,
          evaluation_details: EvaluationDetails.local_override(
            @spec_store.last_config_sync_time,
            @spec_store.initial_config_sync_time
          )
        )
      end
      return nil
    end

    def lookup_config_override(config_name)
      if @config_overrides.key?(config_name)
        return ConfigResult.new(
          name: config_name,
          json_value: @config_overrides[config_name],
          rule_id: Const::OVERRIDE,
          id_type: @spec_store.has_config?(config_name) ? @spec_store.get_config(config_name).id_type : Const::EMPTY_STR,
          evaluation_details: EvaluationDetails.local_override(
            @spec_store.last_config_sync_time,
            @spec_store.initial_config_sync_time
          )
        )
      end
      return nil
    end

    def check_gate(user, gate_name, end_result)
      local_override = lookup_gate_override(gate_name)
      unless local_override.nil?
        end_result.gate_value = local_override.gate_value
        end_result.rule_id = local_override.rule_id
        unless end_result.disable_evaluation_details
          end_result.evaluation_details = local_override.evaluation_details
        end
        return
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

      eval_spec(user, @spec_store.get_gate(gate_name), end_result)
    end

    def get_config(user, config_name, end_result, user_persisted_values: nil)
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
      if !user_persisted_values.nil? && config.is_active == true
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
        eval_spec(user, config, end_result)
        if end_result.is_experiment_group
          @persistent_storage_utils.add_evaluation_to_user_persisted_values(user_persisted_values, config_name,
                                                                            end_result)
          @persistent_storage_utils.save_to_storage(user, config.id_type, user_persisted_values)
        end
        # Otherwise, remove from persisted storage
      else
        @persistent_storage_utils.remove_experiment_from_storage(user, config.id_type, config_name)
        eval_spec(user, config, end_result)
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

      eval_spec(user, @spec_store.get_layer(layer_name), end_result)
    end

    def list_gates
      @spec_store.gates.map { |name, _| name }
    end

    def list_configs
      @spec_store.configs.map { |name, config| name if config.entity == :dynamic_config }.compact
    end

    def list_experiments
      @spec_store.configs.map { |name, config| name if config.entity == :experiment }.compact
    end

    def list_autotunes
      @spec_store.configs.map { |name, config| name if config.entity == :autotune }.compact
    end

    def list_layers
      @spec_store.layers.map { |name, _| name }
    end

    def get_client_initialize_response(user, hash_algo, client_sdk_key, include_local_overrides)
      if @spec_store.is_ready_for_checks == false
        return nil
      end

      evaluated_keys = {}
      if user.user_id.nil? == false
        evaluated_keys[:userID] = user.user_id
      end

      if user.custom_ids.nil? == false
        evaluated_keys[:customIDs] = user.custom_ids
      end

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
        time: 0,
        hash_used: hash_algo,
        user_hash: user.to_hash_without_stable_id
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
      @gate_overrides[gate] = value
    end

    def remove_gate_override(gate)
      @gate_overrides.delete(gate)
    end

    def clear_gate_overrides
      @gate_overrides.clear
    end

    def override_config(config, value)
      @config_overrides[config] = value
    end

    def remove_config_override(config)
      @config_overrides.delete(config)
    end

    def clear_config_overrides
      @config_overrides.clear
    end

    def eval_spec(user, config, end_result)
      unless config.enabled
        finalize_eval_result(config, end_result, did_pass: false, rule: nil)
        return
      end

      config.rules.each do |rule|
        eval_rule(user, rule, end_result)

        if end_result.gate_value
          if eval_delegate(config.name, user, rule, end_result)
            return
          end

          pass = eval_pass_percent(user, rule, config.salt)
          finalize_eval_result(config, end_result, did_pass: pass, rule: rule)
          return
        end
      end

      finalize_eval_result(config, end_result, did_pass: false, rule: nil)
    end

    private

    def finalize_eval_result(config, end_result, did_pass:, rule:)
      end_result.id_type = config.id_type
      end_result.target_app_ids = config.target_app_ids
      end_result.gate_value = did_pass

      if rule.nil?
        end_result.json_value = config.default_value
        end_result.group_name = nil
        end_result.is_experiment_group = false
        end_result.rule_id = config.enabled ? Const::DEFAULT : Const::DISABLED
      else
        end_result.json_value = did_pass ? rule.return_value : config.default_value
        end_result.group_name = rule.group_name
        end_result.is_experiment_group = rule.is_experiment_group == true
        end_result.rule_id = rule.id
      end

      unless end_result.disable_evaluation_details
        end_result.evaluation_details = EvaluationDetails.new(
          @spec_store.last_config_sync_time,
          @spec_store.initial_config_sync_time,
          @spec_store.init_reason
        )
      end
    end

    def eval_rule(user, rule, end_result)
      pass = true
      i = 0
      until i >= rule.conditions.length
        result = eval_condition(user, rule.conditions[i], end_result)

        pass = false if result != true
        i += 1
      end

      end_result.gate_value = pass
    end

    def eval_delegate(name, user, rule, end_result)
      return false unless (delegate = rule.config_delegate)
      return false unless (config = @spec_store.get_config(delegate))

      end_result.undelegated_sec_exps = end_result.secondary_exposures.dup

      eval_spec(user, config, end_result)

      end_result.name = name
      end_result.config_delegate = delegate
      end_result.explicit_parameters = config.explicit_parameters

      true
    end

    def eval_condition(user, condition, end_result)
      value = nil
      field = condition.field
      target = condition.target_value
      type = condition.type
      operator = condition.operator
      additional_values = condition.additional_values
      id_type = condition.id_type

      case type
      when :public
        return true
      when :fail_gate, :pass_gate
        check_gate(user, target, end_result)

        gate_value = end_result.gate_value

        unless end_result.disable_exposures
          new_exposure = {
            gate: target,
            gateValue: gate_value ? Const::TRUE : Const::FALSE,
            ruleID: end_result.rule_id
          }
          end_result.secondary_exposures.append(new_exposure)
        end
        return type == :pass_gate ? gate_value : !gate_value
      when :ip_based
        value = get_value_from_user(user, field) || get_value_from_ip(user, field)
      when :ua_based
        value = get_value_from_user(user, field) || get_value_from_ua(user, field)
      when :user_field
        value = get_value_from_user(user, field)
      when :environment_field
        value = get_value_from_environment(user, field)
      when :current_time
        value = Time.now.to_i # epoch time in seconds
      when :user_bucket
        begin
          salt = additional_values[:salt]
          unit_id = user.get_unit_id(id_type) || Const::EMPTY_STR
          # there are only 1000 user buckets as opposed to 10k for gate pass %
          value = compute_user_hash("#{salt}.#{unit_id}") % 1000
        rescue StandardError
          return false
        end
      when :unit_id
        value = user.get_unit_id(id_type)
      end

      case operator
        # numerical comparison
      when :gt
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a > b })
      when :gte
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a >= b })
      when :lt
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a < b })
      when :lte
        return EvaluationHelpers.compare_numbers(value, target, ->(a, b) { a <= b })

        # version comparison
        # need to check for nil or empty value because Version takes them as valid values
      when :version_gt
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) > Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when :version_gte
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) >= Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when :version_lt
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) < Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when :version_lte
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) <= Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when :version_eq
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) == Gem::Version.new(target)
               rescue StandardError
                 false
               end
      when :version_neq
        return false if value.to_s.empty?

        return begin
                 Gem::Version.new(value) != Gem::Version.new(target)
               rescue StandardError
                 false
               end

        # array operations
      when :any
        return EvaluationHelpers::equal_string_in_array(target, value, true)
      when :none
        return !EvaluationHelpers::equal_string_in_array(target, value, true)
      when :any_case_sensitive
        return EvaluationHelpers::equal_string_in_array(target, value, false)
      when :none_case_sensitive
        return !EvaluationHelpers::equal_string_in_array(target, value, false)

        # string
      when :str_starts_with_any
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.start_with?(b) })
      when :str_ends_with_any
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.end_with?(b) })
      when :str_contains_any
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.include?(b) })
      when :str_contains_none
        return !EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a.include?(b) })
      when :str_matches
        return begin
                 value&.is_a?(String) && !(value =~ Regexp.new(target)).nil?
               rescue StandardError
                 false
               end
      when :eq
        return value == target
      when :neq
        return value != target

        # dates
      when :before
        return EvaluationHelpers.compare_times(value, target, ->(a, b) { a < b })
      when :after
        return EvaluationHelpers.compare_times(value, target, ->(a, b) { a > b })
      when :on
        return EvaluationHelpers.compare_times(value, target, lambda { |a, b|
          a.year == b.year && a.month == b.month && a.day == b.day
        })
      when :in_segment_list, :not_in_segment_list
        begin
          is_in_list = false
          id_list = @spec_store.get_id_list(target)
          if id_list.is_a? IDList
            hashed_id = Digest::SHA256.base64digest(value.to_s)[0, 8]
            is_in_list = id_list.ids.include?(hashed_id)
          end
          return is_in_list if operator == :in_segment_list

          return !is_in_list
        rescue StandardError
          return false
        end
      end
      return false
    end

    def get_value_from_user(user, field)
      return nil unless field.is_a?(String)

      value = get_value_from_user_field(user, field)
      value ||= get_value_from_user_field(user, field.downcase)

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
      unit_id = user.get_unit_id(rule.id_type) || Const::EMPTY_STR
      rule_salt = rule.salt || rule.id || Const::EMPTY_STR
      hash = compute_user_hash("#{config_salt}.#{rule_salt}.#{unit_id}")
      return (hash % 10_000) < (rule.pass_percentage * 100)
    end

    def compute_user_hash(user_hash)
      Digest::SHA256.digest(user_hash).unpack1(Const::Q_RIGHT_CHEVRON)
    end

  end
end
