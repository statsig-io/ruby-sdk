require 'browser'
require 'digest'
require 'evaluation_helpers'
require 'spec_store'

$fetch_from_server = :fetch_from_server
$type_dynamic_config = 'dynamic_config'

class Evaluator
  include EvaluationHelpers

  def initialize(store)
    @spec_store = store
    @initialized = true
  end

  def check_gate(user, gate_name)
    return nil unless @initialized &&
    gate_name.is_a?(String) &&
    @spec_store.has_gate?(gate_name) &&
    user.instance_of?(StatsigUser)

    self.eval_spec(user, @spec_store.get_gate(gate_name))
  end

  def get_config(user, config_name)
    return nil unless @initialized &&
    config_name.is_a?(String) &&
    @spec_store.has_config?(config_name) &&
    user.instance_of?(StatsigUser)

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
          return {
            :name => config['name'],
            :gate_value => pass,
            :config_value => pass ? rule['returnValue'] : config['defaultValue'],
            :rule_id => rule['id']
          }
        end

        i += 1
      end
    end

    {
      :name => config['name'],
      :gate_value => false,
      :config_value => config['defaultValue'],
      :rule_id => 'default'
    }
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

    return $fetch_from_server unless type.is_a?(String)
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
      value = get_value_from_user(user, field) || get_value_from_ip(user['ip'], field)
      return $fetch_from_server if value == $fetch_from_server
    when 'ua_based'
      value = get_value_from_user(user, field) || get_value_from_ua(user['userAgent'], field)
      return $fetch_from_server if value == $fetch_from_server
    when 'user_field'
      value = get_value_from_user(user, field)
    when 'current_time'
      value = Time.now.to_f # epoch time in seconds
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
      return compare_numbers(value, target, ->(a, b) { a > b })
    when 'gte'
      return compare_numbers(value, target, ->(a, b) { a >= b })
    when 'lt'
      return compare_numbers(value, target, ->(a, b) { a < b })
    when 'lte'
      return compare_numbers(value, target, ->(a, b) { a <= b })

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
      return array_contains(target, value)
    when 'none'
      return !array_contains(target, value)

      #string
    when 'str_starts_with_any'
      return match_string_in_array(target, value, ->(a, b) { a.start_with?(b) })
    when 'str_ends_with_any'
      return match_string_in_array(target, value, ->(a, b) { a.end_with?(b) })
    when 'str_contains_any'
      return match_string_in_array(target, value, ->(a, b) { a.include?(b) })
    when 'str_matches'
      return (value.is_a?(String) && !(value =~ Regexp.new(target)).nil? rescue false)
    when 'eq'
      return value == target
    when 'neq'
      return value != target

      # dates
    when 'before'
      # TODO
    when 'after'
      # TODO
    when 'on'
      # TODO
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
  end

  def get_value_from_ip(ip, field)
    return nil unless ip.is_a?(String) && field.is_a?(String)
    # TODO
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
    user_id = user.user_id || ''
    hash = Digest::SHA256.digest("#{salt}.#{rule['name']}.#{user_id}").unpack('Q')[0]
    puts "#{salt}.#{rule['name']}.#{user_id}"
    puts hash
    puts hash % 10000
    hash % 10000 < rule['passPercentage'].to_f * 100
  end
end