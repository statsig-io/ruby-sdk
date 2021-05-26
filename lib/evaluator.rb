require 'spec_store'

$fetch_from_server = :fetch_from_server
$type_dynamic_config = 'dynamic_config'

class Evaluator

  def initialize(api_url_base, server_secret)
    @spec_store = SpecStore.new(api_url_base, server_secret)
    # await @store.init()

    @initialized = true
  end

  def check_gate(user, gate_name)
    return nil unless @initialized && !@spec_store.store[:gates].key?(gate_name).nil?
    self.eval(user, @spec_store.store[:gates][gate_name])
  end

  def get_config(user, config_name)
    return nil unless @initialized && !@spec_store.store[:configs].key?(config_name).nil?
    self.eval(user, @spec_store.store[:configs][config_name])
  end

  private

  def eval(user, config)
    return $fetch_from_server if config['type'].nil?
    type = config['type']

    if config['enabled']
      i = 0
      until i >= config['rules'].length do
        rule = config['rules'][i]
        result = self.eval_rule(user, rule)
        return $fetch_from_server if result == $fetch_from_server
        if result
          pass = self.eval_pass_percent(user, rule, config['salt'])
          value = if type == $type_dynamic_config
                    pass ? rule['returnValue'] : config['defaultValue']
                  else
                    pass
                  end
          return {
            :name => config['name'],
            :value => value,
            :rule_id => rule['id']
          }
        end

        i += 1
      end
    end

    {
      :name => config['name'],
      :value => type == $type_dynamic_config ? config['defaultValue'] : false,
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

  end

  def eval_pass_percent(user, rule, salt)
    # TODO
    true
  end
end