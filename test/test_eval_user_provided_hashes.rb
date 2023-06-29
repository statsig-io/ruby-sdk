# typed: true

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'

require 'statsig'

class EvaluateUserProvidedHashesTest < Minitest::Test

  def setup
    WebMock.enable!
    stub_request(:post, "https://statsigapi.net/v1/get_id_lists")
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs')
      .to_return(status: 200, body: $user_provided_hashes_res)

    @driver = StatsigDriver.new('secret-key')
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_eval_symbol_hash
    custom_hashes = [
      { is_new: true },
      { :is_new => true },
      { "is_new" => true },
      { "is_new": true },
    ]

    custom_hashes.each do |custom_hash|
      user = StatsigUser.new({ userID: 'a-user', custom: custom_hash })
      result = @driver.check_gate(user, 'custom_field_gate')
      assert_equal(true, result)
    end
  end

  def test_eval_private_attributes_symbol_hash
    private_hashes = [
      { is_new: true },
      { :is_new => true },
      { "is_new" => true },
      { "is_new": true },
    ]

    private_hashes.each do |private_hash|
      user = StatsigUser.new({ userID: 'a-user', private_attributes: private_hash })
      result = @driver.check_gate(user, 'custom_field_gate')
      assert_equal(true, result)
    end
  end

  def test_eval_environment
    environment_hashes = [
      { tier: 'development' },
      { :tier => 'development' },
      { "tier" => 'development' },
      { "tier": 'development' },
    ]

    environment_hashes.each do |env_hash|
      user = StatsigUser.new({ userID: 'a-user', statsig_environment: env_hash })
      result = @driver.check_gate(user, 'custom_field_gate')
      assert_equal(true, result)
    end
  end

end

$user_provided_hashes_res = JSON.generate(
  {
    "has_updates": true,
    "dynamic_configs": [],
    "layer_configs": [],
    "feature_gates": [
      { "name": "custom_field_gate",
        "type": "feature_gate",
        "salt": "ae16dbef-d592-4179-b3cf-59134ce70708",
        "enabled": true,
        "defaultValue": false,
        "rules": [
          { "name": "5PnoBPsrq6Y2YPu85fIoyl",
            "groupName": "Is New",
            "passPercentage": 100,
            "conditions": [{ "type": "user_field",
                             "targetValue": ["true"],
                             "operator": "any",
                             "field": "is_new",
                             "additionalValues": { "custom_field": "is_new" },
                             "isDeviceBased": false,
                             "idType": "userID" }],
            "returnValue": true,
            "id": "5PnoBPsrq6Y2YPu85fIoyl",
            "salt": "ad59e707-e14e-462a-89b3-4397c9dc9983",
            "isDeviceBased": false,
            "idType": "userID"
          },
          { "name": "60QzmvFbUuGvpz2iPEFXnO",
            "groupName": "Is Development",
            "passPercentage": 100,
            "conditions": [{
                             "type": "environment_field",
                             "targetValue": ["development"],
                             "operator": "any",
                             "field": "tier",
                             "additionalValues": {},
                             "isDeviceBased": false,
                             "idType": "userID"
                           }],
            "returnValue": true,
            "id": "60QzmvFbUuGvpz2iPEFXnO",
            "salt": "126b37ae-6998-403f-a0ed-43384fe086c3",
            "isDeviceBased": false,
            "idType": "userID"
          }],
        "isDeviceBased": false,
        "idType": "userID",
        "entity": "feature_gate"
      }]
  })