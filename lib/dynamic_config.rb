class DynamicConfig
  attr_accessor :name
  attr_accessor :value
  attr_accessor :rule_id

  def initialize(name, value = {}, rule_id = '')
    @name = name
    @value = value
    @rule_id = rule_id
  end

  def get(index, default_value)
    return default_value if @value.nil? || !@value.key?(index)
    @value[index]
  end
end