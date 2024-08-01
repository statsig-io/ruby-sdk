##
# Contains the current experiment/dynamic config values from Statsig
#
#  Dynamic Config Documentation: https://docs.statsig.com/dynamic-config
#
#  Experiments Documentation: https://docs.statsig.com/experiments-plus
class DynamicConfig

  attr_accessor :name

  attr_accessor :value

  attr_accessor :rule_id

  attr_accessor :group_name

  attr_accessor :id_type

  attr_accessor :evaluation_details

  def initialize(name, value = {}, rule_id = '', group_name = nil, id_type = '', evaluation_details = nil)
    @name = name
    @value = value || {}
    @rule_id = rule_id
    @group_name = group_name
    @id_type = id_type
    @evaluation_details = evaluation_details
  end

  ##
  # Get the value for the given key (index), falling back to the default_value if it cannot be found.
  #
  # @param index The name of parameter being fetched
  # @param default_value The fallback value if the name cannot be found
  def get(index, default_value)
    return default_value if @value.nil?

    index_sym = index.to_sym
    return default_value unless @value.key?(index_sym)

    @value[index_sym]
  end

  ##
  # Get the value for the given key (index), falling back to the default_value if it cannot be found
  # or is found to have a different type from the default_value.
  #
  # @param index The name of parameter being fetched
  # @param default_value The fallback value if the name cannot be found
  def get_typed(index, default_value)
    return default_value if @value.nil?

    index_sym = index.to_sym
    return default_value unless @value.key?(index_sym)

    return default_value if @value[index_sym].class != default_value.class and default_value.class != TrueClass and default_value.class != FalseClass
    @value[index_sym]
  end
end