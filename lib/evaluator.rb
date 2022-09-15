require 'config_result'
require 'country_lookup'
require 'digest'
require 'evaluation_helpers'
require 'client_initialize_helpers'
require 'spec_store'
require 'time'
require 'user_agent_parser'
require 'evaluation_details'
require 'user_agent_parser/operating_system'

$fetch_from_server = 'fetch_from_server'
$type_dynamic_config = 'dynamic_config'

module Statsig
  class Evaluator
    attr_accessor :spec_store

    def initialize(network, options, error_callback)
      @spec_store = Statsig::SpecStore.new(network, error_callback, options.rulesets_sync_interval, options.idlists_sync_interval, options.bootstrap_values)
      @ua_parser = UserAgentParser::Parser.new
      CountryLookup.initialize
      @initialized = true

      @gate_overrides = {}
      @config_overrides = {}
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
          'override',
          [],
          evaluation_details: EvaluationDetails.local_override(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time))
      end

      if !@initialized
        return Statsig::ConfigResult.new(gate_name, evaluation_details: EvaluationDetails.uninitialized)
      end

      if !@spec_store.has_gate?(gate_name)
        return Statsig::ConfigResult.new(gate_name, evaluation_details: EvaluationDetails.unrecognized(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time))
      end

      eval_spec(user, @spec_store.get_gate(gate_name))
    end

    def get_config(user, config_name)
      if @config_overrides.has_key?(config_name)
        return Statsig::ConfigResult.new(
          config_name,
          false,
          @config_overrides[config_name],
          'override',
          [],
          evaluation_details: EvaluationDetails.local_override(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time))
      end

      if !@initialized
        return Statsig::ConfigResult.new(config_name, evaluation_details: EvaluationDetails.uninitialized)
      end

      if !@spec_store.has_config?(config_name)
        return Statsig::ConfigResult.new(config_name, evaluation_details: EvaluationDetails.unrecognized(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time))
      end

      eval_spec(user, @spec_store.get_config(config_name))
    end

    def get_layer(user, layer_name)
      if !@initialized
        return Statsig::ConfigResult.new(layer_name, evaluation_details: EvaluationDetails.uninitialized)
      end

      if !@spec_store.has_layer?(layer_name)
        return Statsig::ConfigResult.new(layer_name, evaluation_details: EvaluationDetails.unrecognized(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time))
      end

      eval_spec(user, @spec_store.get_layer(layer_name))
    end

    def get_client_initialize_response(user)
      if @spec_store.is_ready_for_checks == false
        return nil
      end

      formatter = ClientInitializeHelpers::ResponseFormatter.new(self, user)

      {
        "feature_gates" => formatter.get_responses(:gates),
        "dynamic_configs" => formatter.get_responses(:configs),
        "layer_configs" => formatter.get_responses(:layers),
        "sdkParams" => {},
        "has_updates" => true,
        "generator" => "statsig-ruby-sdk",
        "time" => 0,
      }
    end

    def clean_exposures(exposures)
      seen = {}
      exposures.reject do |exposure|
        key = "#{exposure["gate"]}|#{exposure["gateValue"]}|#{exposure["ruleID"]}}"
        should_reject = seen[key]
        seen[key] = true
        should_reject == true
      end
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

    def eval_spec(user, config)
      default_rule_id = 'default'
      exposures = []
      if config['enabled']
        i = 0
        until i >= config['rules'].length do
          rule = config['rules'][i]
          result = eval_rule(user, rule)
          return $fetch_from_server if result.to_s == $fetch_from_server
          exposures = exposures + result.secondary_exposures
          if result.gate_value

            if (delegated_result = eval_delegate(config['name'], user, rule, exposures))
              return delegated_result
            end

            pass = eval_pass_percent(user, rule, config['salt'])
            return Statsig::ConfigResult.new(
              config['name'],
              pass,
              pass ? result.json_value : config['defaultValue'],
              result.rule_id,
              exposures,
              evaluation_details: EvaluationDetails.network(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time),
              is_experiment_group: result.is_experiment_group,
            )
          end

          i += 1
        end
      else
        default_rule_id = 'disabled'
      end

      Statsig::ConfigResult.new(
        config['name'],
        false,
        config['defaultValue'],
        default_rule_id,
        exposures,
        evaluation_details: EvaluationDetails.network(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time))
    end

    private

    def eval_rule(user, rule)
      exposures = []
      pass = true
      i = 0
      until i >= rule['conditions'].length do
        result = eval_condition(user, rule['conditions'][i])
        if result.to_s == $fetch_from_server
          return $fetch_from_server
        end

        if result.is_a?(Hash)
          exposures = exposures + result['exposures'] if result['exposures'].is_a? Array
          pass = false if result['value'] == false
        elsif result == false
          pass = false
        end
        i += 1
      end

      Statsig::ConfigResult.new(
        '',
        pass,
        rule['returnValue'],
        rule['id'],
        exposures,
        evaluation_details: EvaluationDetails.network(@spec_store.last_config_sync_time, @spec_store.initial_config_sync_time),
        is_experiment_group: rule["isExperimentGroup"] == true)
    end

    def eval_delegate(name, user, rule, exposures)
      return nil unless (delegate = rule['configDelegate'])
      return nil unless (config = @spec_store.get_config(delegate))

      delegated_result = self.eval_spec(user, config)
      return $fetch_from_server if delegated_result.to_s == $fetch_from_server

      delegated_result.name = name
      delegated_result.config_delegate = delegate
      delegated_result.secondary_exposures = exposures + delegated_result.secondary_exposures
      delegated_result.undelegated_sec_exps = exposures
      delegated_result.explicit_parameters = config['explicitParameters']
      delegated_result
    end

    def eval_condition(user, condition)
      value = nil
      field = condition['field']
      target = condition['targetValue']
      type = condition['type']
      operator = condition['operator']
      additional_values = condition['additionalValues']
      additional_values = Hash.new unless additional_values.is_a? Hash
      idType = condition['idType']

      return $fetch_from_server unless type.is_a? String
      type = type.downcase

      case type
      when 'public'
        return true
      when 'fail_gate', 'pass_gate'
        other_gate_result = check_gate(user, target)
        return $fetch_from_server if other_gate_result.to_s == $fetch_from_server

        gate_value = other_gate_result&.gate_value == true
        new_exposure = {
          'gate' => target,
          'gateValue' => gate_value ? 'true' : 'false',
          'ruleID' => other_gate_result&.rule_id
        }
        exposures = other_gate_result&.secondary_exposures&.append(new_exposure)
        return {
          'value' => type == 'pass_gate' ? gate_value : !gate_value,
          'exposures' => exposures
        }
      when 'ip_based'
        value = get_value_from_user(user, field) || get_value_from_ip(user, field)
        return $fetch_from_server if value.to_s == $fetch_from_server
      when 'ua_based'
        value = get_value_from_user(user, field) || get_value_from_ua(user, field)
        return $fetch_from_server if value.to_s == $fetch_from_server
      when 'user_field'
        value = get_value_from_user(user, field)
      when 'environment_field'
        value = get_value_from_environment(user, field)
      when 'current_time'
        value = Time.now.to_f # epoch time in seconds
      when 'user_bucket'
        begin
          salt = additional_values['salt']
          unit_id = get_unit_id(user, idType) || ''
          # there are only 1000 user buckets as opposed to 10k for gate pass %
          value = compute_user_hash("#{salt}.#{unit_id}") % 1000
        rescue
          return false
        end
      when 'unit_id'
        value = get_unit_id(user, idType)
      else
        return $fetch_from_server
      end

      return $fetch_from_server if value.to_s == $fetch_from_server || !operator.is_a?(String)
      operator = operator.downcase

      case operator
        # numerical comparison
      when 'gt'
        return EvaluationHelpers::compare_numbers(value, target, ->(a, b) { a > b })
      when 'gte'
        return EvaluationHelpers::compare_numbers(value, target, ->(a, b) { a >= b })
      when 'lt'
        return EvaluationHelpers::compare_numbers(value, target, ->(a, b) { a < b })
      when 'lte'
        return EvaluationHelpers::compare_numbers(value, target, ->(a, b) { a <= b })

        # version comparison
        # need to check for nil or empty value because Version takes them as valid values
      when 'version_gt'
        return false if value.to_s.empty?
        return (Gem::Version.new(value) > Gem::Version.new(target) rescue false)
      when 'version_gte'
        return false if value.to_s.empty?
        return (Gem::Version.new(value) >= Gem::Version.new(target) rescue false)
      when 'version_lt'
        return false if value.to_s.empty?
        return (Gem::Version.new(value) < Gem::Version.new(target) rescue false)
      when 'version_lte'
        return false if value.to_s.empty?
        return (Gem::Version.new(value) <= Gem::Version.new(target) rescue false)
      when 'version_eq'
        return false if value.to_s.empty?
        return (Gem::Version.new(value) == Gem::Version.new(target) rescue false)
      when 'version_neq'
        return false if value.to_s.empty?
        return (Gem::Version.new(value) != Gem::Version.new(target) rescue false)

        # array operations
      when 'any'
        return EvaluationHelpers::match_string_in_array(target, value, true, ->(a, b) { a == b })
      when 'none'
        return !EvaluationHelpers::match_string_in_array(target, value, true, ->(a, b) { a == b })
      when 'any_case_sensitive'
        return EvaluationHelpers::match_string_in_array(target, value, false, ->(a, b) { a == b })
      when 'none_case_sensitive'
        return !EvaluationHelpers::match_string_in_array(target, value, false, ->(a, b) { a == b })

        #string
      when 'str_starts_with_any'
        return EvaluationHelpers::match_string_in_array(target, value, true, ->(a, b) { a.start_with?(b) })
      when 'str_ends_with_any'
        return EvaluationHelpers::match_string_in_array(target, value, true, ->(a, b) { a.end_with?(b) })
      when 'str_contains_any'
        return EvaluationHelpers::match_string_in_array(target, value, true, ->(a, b) { a.include?(b) })
      when 'str_contains_none'
        return !EvaluationHelpers::match_string_in_array(target, value, true, ->(a, b) { a.include?(b) })
      when 'str_matches'
        return (value.is_a?(String) && !(value =~ Regexp.new(target)).nil? rescue false)
      when 'eq'
        return value == target
      when 'neq'
        return value != target

        # dates
      when 'before'
        return EvaluationHelpers::compare_times(value, target, ->(a, b) { a < b })
      when 'after'
        return EvaluationHelpers::compare_times(value, target, ->(a, b) { a > b })
      when 'on'
        return EvaluationHelpers::compare_times(value, target, ->(a, b) { a.year == b.year && a.month == b.month && a.day == b.day })
      when 'in_segment_list', 'not_in_segment_list'
        begin
          is_in_list = false
          id_list = @spec_store.get_id_list(target)
          if id_list.is_a? IDList
            hashed_id = Digest::SHA256.base64digest(value.to_s)[0, 8]
            is_in_list = id_list.ids.include?(hashed_id)
          end
          return is_in_list if operator == 'in_segment_list'
          return !is_in_list
        rescue
          return false
        end
      else
        return $fetch_from_server
      end
    end

    def get_value_from_user(user, field)
      return nil unless user.instance_of?(StatsigUser) && field.is_a?(String)

      user_lookup_table = user&.value_lookup
      return nil unless user_lookup_table.is_a?(Hash)
      return user_lookup_table[field.downcase] if user_lookup_table.has_key?(field.downcase) && !user_lookup_table[field.downcase].nil?

      user_custom = user_lookup_table['custom']
      if user_custom.is_a?(Hash)
        user_custom.each do |key, value|
          return value if key.downcase.casecmp?(field.downcase) && !value.nil?
        end
      end

      private_attributes = user_lookup_table['privateAttributes']
      if private_attributes.is_a?(Hash)
        private_attributes.each do |key, value|
          return value if key.downcase.casecmp?(field.downcase) && !value.nil?
        end
      end

      nil
    end

    def get_value_from_environment(user, field)
      return nil unless user.instance_of?(StatsigUser) && field.is_a?(String)
      field = field.downcase
      return nil unless user.statsig_environment.is_a? Hash
      user.statsig_environment.each do |key, value|
        return value if key.downcase == (field)
      end
      nil
    end

    def get_value_from_ip(user, field)
      return nil unless user.is_a?(StatsigUser) && field.is_a?(String) && field.downcase == 'country'
      ip = get_value_from_user(user, 'ip')
      return nil unless ip.is_a?(String)

      CountryLookup.lookup_ip_string(ip)
    end

    def get_value_from_ua(user, field)
      return nil unless user.is_a?(StatsigUser) && field.is_a?(String)
      ua = get_value_from_user(user, 'userAgent')
      return nil unless ua.is_a?(String)

      parsed = @ua_parser.parse ua
      os = parsed.os
      case field.downcase
      when 'os_name', 'osname'
        return os&.family
      when 'os_version', 'osversion'
        return os&.version unless os&.version.nil?
      when 'browser_name', 'browsername'
        return parsed.family
      when 'browser_version', 'browserversion'
        return parsed.version.to_s
      else
        nil
      end
    end

    def eval_pass_percent(user, rule, config_salt)
      return false unless config_salt.is_a?(String) && !rule['passPercentage'].nil?
      begin
        unit_id = get_unit_id(user, rule['idType']) || ''
        rule_salt = rule['salt'] || rule['id'] || ''
        hash = compute_user_hash("#{config_salt}.#{rule_salt}.#{unit_id}")
        return (hash % 10000) < (rule['passPercentage'].to_f * 100)
      rescue
        return false
      end
    end

    def get_unit_id(user, id_type)
      if id_type.is_a?(String) && id_type.downcase != 'userid'
        return nil unless user&.custom_ids.is_a? Hash
        return user.custom_ids[id_type] || user.custom_ids[id_type.downcase]
      end
      user.user_id
    end

    def compute_user_hash(user_hash)
      Digest::SHA256.digest(user_hash).unpack('Q>')[0]
    end
  end
end