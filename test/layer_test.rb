# typed: true

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'layer'

class LayerTest < Minitest::Test

  def setup
    @layer = Layer.new("test", {
      "bool" => true,
      "number" => 2,
      "string" => 'string',
      "object" =>  {
        key: 'value',
        key2: 123,
      },
      "boolStr1" => 'true',
      "boolStr2" => 'FALSE',
      "numberStr1" => '3',
      "numberStr2" => '3.3',
      "numberStr3" => '3.3.3',
      "arr" => [1, 2, 'three'],
    })
  end

  def test_typed_getter
    assert(@layer.get_typed('bool', false) == true)
    assert(@layer.get_typed('number', 0) == 2)
    assert(@layer.get_typed('string', 'default') == 'string')
    assert(@layer.get_typed("object", {}) == {
      key: 'value',
      key2: 123,
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
      key: 'value',
      key2: 123,
    })
    assert(@layer.get("arr", []) == [1, 2, 'three'])

    assert(@layer.get("bool", "string") == true)
    assert(@layer.get("number", "string") == 2)
    assert(@layer.get("string", 6) == 'string')
    assert(@layer.get("numberStr2", 3.3) == '3.3')
    assert(@layer.get("object", "string") == {
      key: 'value',
      key2: 123,
    })
    assert(@layer.get("arr", 12) == [1, 2, 'three'])
  end

end