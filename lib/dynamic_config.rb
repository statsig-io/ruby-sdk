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

  def get_typed(index, default_value)
    return default_value if @value.nil? || !@value.key?(index)
    return default_value if @value[index].class != default_value.class and default_value.class != TrueClass and default_value.class != FalseClass
    @value[index]
  end
end