##
# Contains the current values from Statsig.
# Will contain layer default values for all shared parameters in that layer.
# If a parameter is in an active experiment, and the current user is allocated to that experiment,
# those parameters will be updated to reflect the experiment values not the layer defaults.
#
# Layers Documentation: https://docs.statsig.com/layers
class Layer

  attr_accessor :name

  attr_accessor :rule_id

  attr_accessor :group_name

  def initialize(name, value = {}, rule_id = '', group_name = nil, allocated_experiment = nil, exposure_log_func = nil)
    @name = name
    @value = value || {}
    @rule_id = rule_id
    @group_name = group_name
    @allocated_experiment = allocated_experiment
    @exposure_log_func = exposure_log_func
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

    if @exposure_log_func.is_a? Proc
      @exposure_log_func.call(self, index)
    end

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

    if @exposure_log_func.is_a? Proc
      @exposure_log_func.call(self, index)
    end

    @value[index_sym]
  end
end
