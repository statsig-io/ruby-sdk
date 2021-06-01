class ConfigResult
  attr_accessor :name
  attr_accessor :gate_value
  attr_accessor :json_value
  attr_accessor :rule_id

  def initialize(name, gate_value = false, json_value = {}, rule_id = '')
    @name = name
    @gate_value = gate_value
    @json_value = json_value
    @rule_id = rule_id
  end
end