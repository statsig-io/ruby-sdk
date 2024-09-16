

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'layer'

class LayerTest < BaseTest
  suite :LayerTest
  def setup
    super
    @layer = Layer.new("test", {
      :bool => true,
      :number => 2,
      :float_number => 3.14,
      :string => 'string',
      :object =>  {
        key: 'value',
        key2: 123,
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
    assert(@layer.get_typed('bool', false) == true)
    assert(@layer.get_typed('number', 0) == 2)
    assert(@layer.get_typed('string', 'default') == 'string')
    assert(@layer.get_typed("object", {}) == {
      "key": 'value',
      "key2": 123,
    })
    assert(@layer.get_typed("arr", []) == [1, 2, 'three'])

    assert(@layer.get_typed("bool", "string") == "string")
    assert(@layer.get_typed("number", "string") == "string")
    assert(@layer.get_typed("string", 6) == 6)
    assert(@layer.get_typed("numberStr2", 3.3) == 3.3)
    assert(@layer.get_typed("object", "string") == "string")
    assert(@layer.get_typed("arr", 2) == 2)
  end

  def test_getter
    assert(@layer.get('bool', false) == true)
    assert(@layer.get('number', 0) == 2)
    assert(@layer.get('string', 'default') == 'string')
    assert(@layer.get("object", {}) == {
      "key": 'value',
      "key2": 123,
    })
    assert(@layer.get("arr", []) == [1, 2, 'three'])

    assert(@layer.get("bool", "string") == true)
    assert(@layer.get("number", "string") == 2)
    assert(@layer.get("string", 6) == 'string')
    assert(@layer.get("numberStr2", 3.3) == '3.3')
    assert(@layer.get("object", "string") == {
      "key": 'value',
      "key2": 123,
    })
    assert(@layer.get("arr", 12) == [1, 2, 'three'])
  end

  def test_typed_getter_numeric_conversions
    assert_equal(2.0, @layer.get_typed('number', 0.0))
    assert_equal(3, @layer.get_typed('float_number', 0))
    
    assert_equal(0, @layer.get_typed('numberStr3', 0))
    assert_equal(0.0, @layer.get_typed('numberStr3', 0.0))

    assert_equal(42, @layer.get_typed('non_existent', 42))
    assert_equal(42.5, @layer.get_typed('non_existent', 42.5))
  end

  def test_typed_getter_edge_cases
    assert_equal(0, @layer.get_typed('bool', 0))
    assert_equal(0.0, @layer.get_typed('bool', 0.0))
    
    assert_equal(false, @layer.get_typed('number', false))
    assert_equal(false, @layer.get_typed('float_number', false))
    
    assert_equal(42, @layer.get_typed('arr', 42))
    assert_equal(42.5, @layer.get_typed('arr', 42.5))
    
    assert_equal(42, @layer.get_typed('object', 42))
    assert_equal(42.5, @layer.get_typed('object', 42.5))
  end

end