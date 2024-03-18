require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'

require 'statsig'

class APIConfigTest < BaseTest
  suite :APIConfigTest

  def test_partial_api_config_deserialize
    data = {
      name: 'a_partial_config',
      type: 'dynamic_config',
      salt: '24970d78-06f9-42ea-8d81-ec6b213129bc',
      enabled: true,
      defaultValue: {
        a_num: 123,
        a_string: 'foo',
        a_bool: true
      },
      rules: [],
      idType: 'userID'
    }

    config = Statsig::APIConfig.from_json(data)
    assert_equal('a_partial_config', config.name)
    assert_equal(:dynamic_config, config.type)
    assert_equal('24970d78-06f9-42ea-8d81-ec6b213129bc', config.salt)
    assert_equal(true, config.enabled)
    assert_equal({ 'a_num' => 123, 'a_string' => 'foo', 'a_bool' => true }, config.default_value)
    assert_equal([], config.rules)
    assert_equal('userID', config.id_type)
    assert_nil(config.entity)
  end

  def test_full_api_config_deserialize
    data = {
      "name": 'a_full_config',
      "type": 'dynamic_config',
      "salt": 'd3cf0a17-42dd-45cb-affe-00a7ac89a545',
      "enabled": true,
      "defaultValue": {
        "foo": 1e+21
      },
      "rules": [],
      "isDeviceBased": false,
      "idType": 'userID',
      "entity": 'experiment'
    }

    config = Statsig::APIConfig.from_json(data)
    assert_equal('a_full_config', config.name)
    assert_equal(:dynamic_config, config.type)
    assert_equal('d3cf0a17-42dd-45cb-affe-00a7ac89a545', config.salt)
    assert_equal(true, config.enabled)
    assert_equal({ 'foo' => 1.0e+21 }, config.default_value)
    assert_equal([], config.rules)
    assert_equal('userID', config.id_type)
    assert_equal(:experiment, config.entity)
  end

  def test_rule_deserialize
    data = {
      "name": '6P9DkjwTzCWkWBELUhTySP',
      "passPercentage": 100,
      "conditions": [],
      "returnValue": {
        "header_text": '[dev only] test'
      },
      "id": '6P9DkjwTzCWkWBELUhTySP',
      "salt": 'c3250411-98cb-48e3-884d-a1f0560314d0',
      "isDeviceBased": false,
      "idType": 'userID',
      "isExperimentGroup": true
    }

    rule = Statsig::APIRule.from_json(data)
    assert_equal('6P9DkjwTzCWkWBELUhTySP', rule.name)
    assert_equal(100, rule.pass_percentage)
    assert_equal([], rule.conditions)
    assert_equal({ 'header_text' => '[dev only] test' }, rule.return_value)
    assert_equal('6P9DkjwTzCWkWBELUhTySP', rule.id)
    assert_equal('c3250411-98cb-48e3-884d-a1f0560314d0', rule.salt)
    assert_equal('userID', rule.id_type)
    assert_equal(true, rule.is_experiment_group)
  end

  def test_condition_deserialize
    data = {
      "type": 'environment_field',
      "targetValue": %w[staging development],
      "operator": 'any',
      "field": 'tier',
      "additionalValues": {
        "salt": '5b965836-85f6-4a8d-b9a4-8ef76c5dbd47'
      },
      "isDeviceBased": false,
      "idType": 'userID'
    }

    condition = Statsig::APICondition.from_json(data)
    assert_equal(:environment_field, condition.type)
    assert_equal({"staging" => true, "development" => true}, condition.target_value)
    assert_equal(:any, condition.operator)
    assert_equal({ salt: '5b965836-85f6-4a8d-b9a4-8ef76c5dbd47' }, condition.additional_values)
    assert_equal('userID', condition.id_type)
  end
end
