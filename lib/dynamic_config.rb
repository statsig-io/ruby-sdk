class DynamicConfig
  attr_accessor :name
  attr_accessor :value
  attr_accessor :rule_id

  def initialize(name)
    @name = name
    @value = {}
    @rule_id = nil
  end

  def get(index)
    return nil if @value.nil?
    value[index]
  end
end