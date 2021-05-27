class DynamicConfig
  attr_accessor :name
  attr_accessor :value
  attr_accessor :rule_id

  def from_json(config_json)
    @name = config_json['name']
    @value = config_json['value']
    @rule_id = config_json['rule_id']
  end

  def get(index)
    return nil if @value.nil?
    value[index]
  end
end