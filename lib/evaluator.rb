require 'browser'
require 'config_result'
require 'digest'
require 'evaluation_helpers'
require 'spec_store'

$fetch_from_server = :fetch_from_server
$type_dynamic_config = 'dynamic_config'

class Evaluator
  def initialize(store)
    @spec_store = store
    @initialized = true
  end

  def check_gate(user, gate_name)
    return nil unless @initialized && @spec_store.has_gate?(gate_name)
    self.eval_spec(user, @spec_store.get_gate(gate_name))
  end

  def get_config(user, config_name)
    return nil unless @initialized && @spec_store.has_config?(config_name)
    self.eval_spec(user, @spec_store.get_config(config_name))
  end

  private

  def eval_spec(user, config)
    if config['enabled']
      i = 0
      until i >= config['rules'].length do
        rule = config['rules'][i]
        result = self.eval_rule(user, rule)
        return $fetch_from_server if result == $fetch_from_server
        if result
          pass = self.eval_pass_percent(user, rule, config['salt'])
          return ConfigResult.new(
            config['name'],
            pass,
            pass ? rule['returnValue'] : config['defaultValue'],
            rule['id'],
          )
        end

        i += 1
      end
    end

    ConfigResult.new(config['name'], false, config['defaultValue'], 'default')
  end

  def eval_rule(user, rule)
    i = 0
    until i >= rule['conditions'].length do
      result = self.eval_condition(user, rule['conditions'][i])
      return result unless result == true
      i += 1
    end
    true
  end

  def eval_condition(user, condition)
    value = nil
    field = condition['field']
    target = condition['targetValue']
    type = condition['type']
    operator = condition['operator']
    additional_values = condition['additionalValues']
    additional_values = Hash.new unless additional_values.is_a? Hash

    return $fetch_from_server unless type.is_a? String
    type = type.downcase

    case type
    when 'public'
      return true
    when 'fail_gate'
    when 'pass_gate'
      other_gate_result = self.check_gate(user, target)
      return $fetch_from_server if other_gate_result == $fetch_from_server
      return type == 'pass_gate' ? other_gate_result[:gate_value] : !other_gate_result[:gate_value]
    when 'ip_based'
      value = get_value_from_user(user, field) || get_value_from_ip(user&.value_lookup['ip'], field)
      return $fetch_from_server if value == $fetch_from_server
    when 'ua_based'
      value = get_value_from_user(user, field) || get_value_from_ua(user&.value_lookup['userAgent'], field)
      return $fetch_from_server if value == $fetch_from_server
    when 'user_field'
      value = get_value_from_user(user, field)
    when 'environment_field'
      value = get_value_from_environment(user, field)
    when 'current_time'
      value = Time.now.to_f # epoch time in seconds
    when 'user_bucket'
      salt = additional_values['salt']
      user_id = user.user_id || ''
      value = compute_user_hash_bucket("#{salt}.#{user_id}")
    else
      return $fetch_from_server
    end

    return $fetch_from_server if value == $fetch_from_server
    return false if value.nil?

    return $fetch_from_server unless operator.is_a?(String)
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
      return EvaluationHelpers::array_contains(target, value)
    when 'none'
      return !EvaluationHelpers::array_contains(target, value)

      #string
    when 'str_starts_with_any'
      return EvaluationHelpers::match_string_in_array(target, value, ->(a, b) { a.start_with?(b) })
    when 'str_ends_with_any'
      return EvaluationHelpers::match_string_in_array(target, value, ->(a, b) { a.end_with?(b) })
    when 'str_contains_any'
      return EvaluationHelpers::match_string_in_array(target, value, ->(a, b) { a.include?(b) })
    when 'str_matches'
      return (value.is_a?(String) && !(value =~ Regexp.new(target)).nil? rescue false)
    when 'eq'
      return value == target
    when 'neq'
      return value != target

      # dates
    when 'before'
      # TODO - planned future conditions
    when 'after'
      # TODO - planned future conditions
    when 'on'
      # TODO - planned future conditions
    else
      return $fetch_from_server
    end
  end

  def get_value_from_user(user, field)
    return nil unless user.instance_of?(StatsigUser) && field.is_a?(String)

    user_lookup_table = user&.value_lookup
    return nil unless user_lookup_table.is_a?(Hash)
    return user_lookup_table[field.downcase] if user_lookup_table.has_key?(field.downcase)

    user_custom = user_lookup_table['custom']
    return nil unless user_custom.is_a?(Hash)
    user_custom.each do |key, value|
      return value if key.downcase.casecmp(field.downcase)
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

  def get_value_from_ip(ip, field)
    return nil unless ip.is_a?(String) && field.is_a?(String)
    # TODO: add IP3 country for local evaluation
    $fetch_from_server
  end

  def get_value_from_ua(ua, field)
    return nil unless ua.is_a?(String) && field.is_a?(String)
    b = Browser.new(ua)
    case field.downcase
    when 'os_name'
      os_name = b.platform.name
      # special case for iOS because value is 'iOS (iPhone)'
      if os_name.include?('iOS') || os_name.include?('ios')
        return 'iOS'
      else
        return os_name
      end
    when 'os_version'
      return b.platform.version
    when 'browser_name'
      return b.name
    when 'browser_version'
      return b.full_version
    else
      nil
    end
  end

  def eval_pass_percent(user, rule, salt)
    return false unless salt.is_a?(String) && !rule['passPercentage'].nil?
    begin
      user_id = user.user_id || ''
      bucket = compute_user_hash_bucket("#{salt}.#{rule['id']}.#{user_id}")
      return bucket < (rule['passPercentage'].to_f * 100)
    rescue
      return false
    end
  end

  def compute_user_hash_bucket(user_hash)
    begin
      hash = Digest::SHA256.digest(user_hash).unpack('Q>')[0]
      return hash % 10000
    rescue
      # if any error is raised, we return a value that will never pass any user hash bucket
      return 10000 * 2
    end
  end
end