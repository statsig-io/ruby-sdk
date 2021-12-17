require 'config_result'
require 'country_lookup'
require 'digest'
require 'evaluation_helpers'
require 'spec_store'
require 'time'
require 'user_agent_parser'
require 'user_agent_parser/operating_system'

$fetch_from_server = :fetch_from_server
$type_dynamic_config = 'dynamic_config'

class Evaluator
  def initialize(network, error_callback)
    @spec_store = SpecStore.new(network, error_callback)
    @ua_parser = UserAgentParser::Parser.new
    CountryLookup.initialize
    @initialized = true
  end

  def check_gate(user, gate_name)
    return nil unless @initialized && @spec_store.has_gate?(gate_name)
    eval_spec(user, @spec_store.get_gate(gate_name))
  end

  def get_config(user, config_name)
    return nil unless @initialized && @spec_store.has_config?(config_name)
    eval_spec(user, @spec_store.get_config(config_name))
  end

  def shutdown
    @spec_store.shutdown
  end

  private

  def eval_spec(user, config)
    default_rule_id = 'default'
    exposures = []
    if config['enabled']
      i = 0
      until i >= config['rules'].length do
        rule = config['rules'][i]
        result = eval_rule(user, rule)
        return $fetch_from_server if result == $fetch_from_server
        exposures = exposures + result['exposures'] if result['exposures'].is_a? Array
        if result['value']
          pass = eval_pass_percent(user, rule, config['salt'])
          return ConfigResult.new(
            config['name'],
            pass,
            pass ? rule['returnValue'] : config['defaultValue'],
            rule['id'],
            exposures
          )
        end

        i += 1
      end
    else
      default_rule_id = 'disabled'
    end

    ConfigResult.new(config['name'], false, config['defaultValue'], default_rule_id, exposures)
  end

  def eval_rule(user, rule)
    exposures = []
    pass = true
    i = 0
    until i >= rule['conditions'].length do
      result = eval_condition(user, rule['conditions'][i])
      if result == $fetch_from_server
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
    { 'value' => pass, 'exposures' => exposures }
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
      return $fetch_from_server if other_gate_result == $fetch_from_server

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
      return $fetch_from_server if value == $fetch_from_server
    when 'ua_based'
      value = get_value_from_user(user, field) || get_value_from_ua(user, field)
      return $fetch_from_server if value == $fetch_from_server
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

    return $fetch_from_server if value == $fetch_from_server || !operator.is_a?(String)
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
    when 'version_gt'
      return (Gem::Version.new(value) > Gem::Version.new(target) rescue false)
    when 'version_gte'
      return (Gem::Version.new(value) >= Gem::Version.new(target) rescue false)
    when 'version_lt'
      return (Gem::Version.new(value) < Gem::Version.new(target) rescue false)
    when 'version_lte'
      return (Gem::Version.new(value) <= Gem::Version.new(target) rescue false)
    when 'version_eq'
      return (Gem::Version.new(value) == Gem::Version.new(target) rescue false)
    when 'version_neq'
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
      id_list = (@spec_store.get_id_list(target) || {:ids => {}})[:ids]
      hashed_id = Digest::SHA256.base64digest(value.to_s)[0, 8]    
      is_in_list = id_list.is_a?(Hash) && id_list[hashed_id] == true
      
      return is_in_list if operator == 'in_segment_list'
      return !is_in_list
      rescue StandardError => e
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
      unit_id = get_unit_id(user, rule['id_type']) || ''
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