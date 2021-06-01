class DynamicConfig
  attr_accessor :name
  attr_accessor :value
  attr_accessor :rule_id

  def initialize(name, value = {}, rule_id = '')
    @name = name
    @value = value
    @rule_id = rule_id
  end

  def get(index)
    return nil if @value.nil?
    value[index]
  end
end