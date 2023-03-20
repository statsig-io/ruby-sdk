# typed: false

require 'sorbet-runtime'

##
# Contains the current experiment/dynamic config values from Statsig
#
#  Dynamic Config Documentation: https://docs.statsig.com/dynamic-config
#
#  Experiments Documentation: https://docs.statsig.com/experiments-plus
class DynamicConfig
  extend T::Sig

  sig { returns(String) }
  attr_accessor :name

  sig { returns(T::Hash[String, T.untyped]) }
  attr_accessor :value

  sig { returns(String) }
  attr_accessor :rule_id

  sig { returns(T.nilable(String)) }
  attr_accessor :group_name

  sig { params(name: String, value: T::Hash[String, T.untyped], rule_id: String, group_name: T.nilable(String)).void }
  def initialize(name, value = {}, rule_id = '', group_name = nil)
    @name = name
    @value = value
    @rule_id = rule_id
    @group_name = group_name
  end

  sig { params(index: String, default_value: T.untyped).returns(T.untyped) }
  ##
  # Get the value for the given key (index), falling back to the default_value if it cannot be found.
  #
  # @param index The name of parameter being fetched
  # @param default_value The fallback value if the name cannot be found
  def get(index, default_value)
    return default_value if @value.nil? || !@value.key?(index)
    @value[index]
  end

  sig { params(index: String, default_value: T.untyped).returns(T.untyped) }
  ##
  # Get the value for the given key (index), falling back to the default_value if it cannot be found
  # or is found to have a different type from the default_value.
  #
  # @param index The name of parameter being fetched
  # @param default_value The fallback value if the name cannot be found
  def get_typed(index, default_value)
    return default_value if @value.nil? || !@value.key?(index)
    return default_value if @value[index].class != default_value.class and default_value.class != TrueClass and default_value.class != FalseClass
    @value[index]
  end
end