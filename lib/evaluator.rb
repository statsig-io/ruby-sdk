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
    UNSUPPORTED_EVALUATION = :unsupported_eval

    attr_accessor :spec_store

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

    def check_gate(user, gate_name)
      if @gate_overrides.has_key?(gate_name)
        return Statsig::ConfigResult.new(
          gate_name,
          @gate_overrides[gate_name],
          @gate_overrides[gate_name],
          Const::OVERRIDE,
          [],
          evaluation_details: EvaluationDetails.local_override(@spec_store.last_config_sync_time,
                                                               @spec_store.initial_config_sync_time)
        )
      end

      if @spec_store.init_reason == EvaluationReason::UNINITIALIZED
        return Statsig::ConfigResult.new(gate_name, evaluation_details: EvaluationDetails.uninitialized)
      end

      unless @spec_store.has_gate?(gate_name)
        return Statsig::ConfigResult.new(gate_name,
                                         evaluation_details: EvaluationDetails.unrecognized(@spec_store.last_config_sync_time,
                                                                                            @spec_store.initial_config_sync_time))
      end

      result = Statsig::ConfigResult.new(gate_name)
      eval_spec(user, @spec_store.get_gate(gate_name), result)
      result
    end

    def get_config(user, config_name, user_persisted_values: nil)
      if @config_overrides.key?(config_name)
        id_type = @spec_store.has_config?(config_name) ? @spec_store.get_config(config_name).id_type : Const::EMPTY_STR
        return Statsig::ConfigResult.new(
          config_name,
          false,
          @config_overrides[config_name],
          Const::OVERRIDE,
          [],
          evaluation_details: EvaluationDetails.local_override(
            @spec_store.last_config_sync_time,
            @spec_store.initial_config_sync_time
          ),
          id_type: id_type
        )
      end

      if @spec_store.init_reason == EvaluationReason::UNINITIALIZED
        return Statsig::ConfigResult.new(config_name, evaluation_details: EvaluationDetails.uninitialized)
      end

      unless @spec_store.has_config?(config_name)
        return Statsig::ConfigResult.new(
          config_name,
          evaluation_details: EvaluationDetails.unrecognized(
            @spec_store.last_config_sync_time,
            @spec_store.initial_config_sync_time
          )
        )
      end

      config = @spec_store.get_config(config_name)

      # If persisted values is provided and the experiment is active, return sticky values if exists.
      if !user_persisted_values.nil? && config.is_active == true
        sticky_result = Statsig::ConfigResult.from_user_persisted_values(config_name, user_persisted_values)
        return sticky_result unless sticky_result.nil?

        # If it doesn't exist, then save to persisted storage if the user was assigned to an experiment group.
        result = Statsig::ConfigResult.new(config_name)
        eval_spec(user, config, result)
        if result.is_experiment_group
          @persistent_storage_utils.add_evaluation_to_user_persisted_values(user_persisted_values, config_name, result)
          @persistent_storage_utils.save_to_storage(user, config.id_type, user_persisted_values)
        end
        # Otherwise, remove from persisted storage
      else
        @persistent_storage_utils.remove_experiment_from_storage(user, config.id_type, config_name)
        result = Statsig::ConfigResult.new(config_name)
        eval_spec(user, config, result)
      end
      result
    end

    def get_layer(user, layer_name)
      if @spec_store.init_reason == EvaluationReason::UNINITIALIZED
        return Statsig::ConfigResult.new(layer_name, evaluation_details: EvaluationDetails.uninitialized)
      end

      unless @spec_store.has_layer?(layer_name)
        return Statsig::ConfigResult.new(layer_name,
                                         evaluation_details: EvaluationDetails.unrecognized(@spec_store.last_config_sync_time,
                                                                                            @spec_store.initial_config_sync_time))
      end

      result = Statsig::ConfigResult.new(layer_name)
      eval_spec(user, @spec_store.get_layer(layer_name), result)
      result
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

    def get_client_initialize_response(user, hash_algo, client_sdk_key)
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
        feature_gates: Statsig::ResponseFormatter.get_responses(@spec_store.gates, self, user, client_sdk_key,
                                                                hash_algo),
        dynamic_configs: Statsig::ResponseFormatter.get_responses(@spec_store.configs, self, user, client_sdk_key,
                                                                  hash_algo),
        layer_configs: Statsig::ResponseFormatter.get_responses(@spec_store.layers, self, user, client_sdk_key,
                                                                hash_algo),
        sdkParams: {},
        has_updates: true,
        generator: Const::STATSIG_RUBY_SDK,
        evaluated_keys: evaluated_keys,
        time: 0,
        hash_used: hash_algo,
        user_hash: user.to_hash_without_stable_id
      }
    end

    def get_all_evaluations(user)
      if @spec_store.is_ready_for_checks == false
        return nil
      end

      {
        feature_gates: Statsig::ResponseFormatter.get_responses(@spec_store.gates, self, user, nil, 'none'),
        dynamic_configs: Statsig::ResponseFormatter.get_responses(@spec_store.configs, self, user, nil, 'none'),
        layer_configs: Statsig::ResponseFormatter.get_responses(@spec_store.layers, self, user, nil, 'none')
      }
    end

    def shutdown
      @spec_store.shutdown
    end

    def override_gate(gate, value)
      @gate_overrides[gate] = value
    end

    def override_config(config, value)
      @config_overrides[config] = value
    end

    def eval_spec(user, config, end_result)
      end_result.id_type = config.id_type
      end_result.target_app_ids = config.target_app_ids
      end_result.evaluation_details = EvaluationDetails.new(
        @spec_store.last_config_sync_time,
        @spec_store.initial_config_sync_time,
        @spec_store.init_reason
      )
      default_rule_id = Const::DEFAULT
      if config.enabled
        i = 0
        until i >= config.rules.length
          rule = config.rules[i]
          eval_rule(user, rule, end_result)

          if end_result.gate_value
            if eval_delegate(config.name, user, rule, end_result)
              return
            end

            pass = eval_pass_percent(user, rule, config.salt)
            end_result.gate_value = pass
            end_result.json_value = pass ? rule.return_value : config.default_value
            end_result.rule_id = rule.id
            end_result.group_name = rule.group_name
            end_result.is_experiment_group = rule.is_experiment_group == true
            return
          end

          i += 1
        end
      else
        default_rule_id = Const::DISABLED
      end

      end_result.rule_id = default_rule_id
      end_result.gate_value = false
      end_result.json_value = config.default_value
      end_result.evaluation_details = EvaluationDetails.new(
        @spec_store.last_config_sync_time,
        @spec_store.initial_config_sync_time,
        @spec_store.init_reason
      )
      end_result.group_name = nil
    end

    private

    def eval_rule(user, rule, end_result)
      pass = true
      i = 0
      until i >= rule.conditions.length
        result = eval_condition(user, rule.conditions[i], end_result)

        pass = false if result == false
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
        other_gate_result = check_gate(user, target)

        gate_value = other_gate_result.gate_value
        new_exposure = {
          gate: target,
          gateValue: gate_value ? Const::TRUE : Const::FALSE,
          ruleID: other_gate_result.rule_id
        }
        if other_gate_result.secondary_exposures.length > 0
          end_result.secondary_exposures.concat(other_gate_result.secondary_exposures)
        end
        end_result.secondary_exposures.append(new_exposure)
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
        return EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a == b })
      when :none
        return !EvaluationHelpers.match_string_in_array(target, value, true, ->(a, b) { a == b })
      when :any_case_sensitive
        return EvaluationHelpers.match_string_in_array(target, value, false, ->(a, b) { a == b })
      when :none_case_sensitive
        return !EvaluationHelpers.match_string_in_array(target, value, false, ->(a, b) { a == b })

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
          value.is_a?(String) && !(value =~ Regexp.new(target)).nil?
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
      value = case field.downcase
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
              end
      if value.nil?
        value = user.custom[field] if user.custom.is_a?(Hash)
        value = user.custom[field.to_sym] if value.nil? && user.custom.is_a?(Hash)
        value = user.private_attributes[field] if value.nil? && user.private_attributes.is_a?(Hash)
        value = user.private_attributes[field.to_sym] if value.nil? && user.private_attributes.is_a?(Hash)
      end
      value
    end

    def get_value_from_environment(user, field)
      return nil unless user.statsig_environment.is_a? Hash

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
    rescue StandardError
      return false
    end

    def compute_user_hash(user_hash)
      Digest::SHA256.digest(user_hash).unpack1(Const::Q_RIGHT_CHEVRON)
    end
  end
end
