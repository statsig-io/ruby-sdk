

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'dynamic_config'

class DynamicConfigTest < BaseTest
  suite :DynamicConfigTest

  def setup
    super
    @config = DynamicConfig.new("test", {
      :bool => true,
      :number => 2,
      :float_number => 3.14,
      :string => 'string',
      :object =>  {
        "key": 'value',
        "key2": 123,
      },
      :boolStr1 => 'true',
      :boolStr2 => 'FALSE',
      :numberStr1 => '3',
      :numberStr2 => '3.3',
      :numberStr3 => '3.3.3',
      :arr => [1, 2, 'three'],
    })
  end

  def test_typed_getter
    assert(@config.get_typed('bool', false) == true)
    assert(@config.get_typed('number', 0) == 2)
    assert(@config.get_typed('string', 'default') == 'string')
    assert(@config.get_typed("object", {}) == {
      "key": 'value',
      "key2": 123,
    })
    assert(@config.get_typed("arr", []) == [1, 2, 'three'])

    assert(@config.get_typed("bool", "string") == "string")
    assert(@config.get_typed("number", "string") == "string")
    assert(@config.get_typed("string", 6) == 6)
    assert(@config.get_typed("numberStr1", 3.3) == 3.3)
    assert(@config.get_typed("object", "string") == "string")
    assert(@config.get_typed("arr", 2) == 2)
  end

  def test_getter
    assert(@config.get('bool', false) == true)
    assert(@config.get('number', 0) == 2)
    assert(@config.get('string', 'default') == 'string')
    assert(@config.get("object", {}) == {
      "key": 'value',
      "key2": 123,
    })
    assert(@config.get("arr", []) == [1, 2, 'three'])
    assert(@config.get("bool", "string") == true)
    assert(@config.get("number", "string") == 2)
    assert(@config.get("string", 6) == 'string')
    assert(@config.get("numberStr2", 3.3) == '3.3')
    assert(@config.get("object", "string") == {
      "key": 'value',
      "key2": 123,
    })
    assert(@config.get("arr", 12) == [1, 2, 'three'])
  end

  def test_typed_getter_numeric_conversions
    assert_equal(2.0, @config.get_typed('number', 0.0))
    
    assert_equal(3, @config.get_typed('float_number', 0))
    
    assert_equal(0, @config.get_typed('numberStr3', 0))
    assert_equal(0.0, @config.get_typed('numberStr3', 0.0))
    
    assert_equal(42, @config.get_typed('non_existent', 42))
    assert_equal(42.5, @config.get_typed('non_existent', 42.5))
  end

  def test_typed_getter_edge_cases
    assert_equal(0, @config.get_typed('bool', 0))
    assert_equal(1.0, @config.get_typed('bool', 1.0))

    assert_equal(false, @config.get_typed('number', false))
    assert_equal(false, @config.get_typed('float_number', false))
    
    assert_equal(42, @config.get_typed('arr', 42))
    assert_equal(42.5, @config.get_typed('arr', 42.5))
    
    assert_equal(42, @config.get_typed('object', 42))
    assert_equal(42.5, @config.get_typed('object', 42.5))
  end

end