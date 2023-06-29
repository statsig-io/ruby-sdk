# typed: true

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'

require 'statsig'

$expected_sync_time = 1631638014811

class EvaluationDetailsTest < Minitest::Test
  def setup
    super
    WebMock.enable!
    @json_file = File.read("#{__dir__}/data/download_config_specs.json")
    @mock_response = JSON.parse(@json_file).to_json
    @user = StatsigUser.new({ 'user_id' => 'a-user' })

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @mock_response)
    driver = StatsigDriver.new('secret-key')

    @evaluator = driver.instance_variable_get('@evaluator')
    @store = @evaluator.instance_variable_get('@spec_store')
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_uninitialized
    @store.instance_variable_set('@init_reason', "Uninitialized")
    result = @evaluator.check_gate(@user, 'not_a_gate')
    assert_equal("Uninitialized", result.evaluation_details.reason)
    assert_equal(0, result.evaluation_details.config_sync_time)

    result = @evaluator.get_config(@user, 'not_a_config')
    assert_equal("Uninitialized", result.evaluation_details.reason)
    assert_equal(0, result.evaluation_details.config_sync_time)

    result = @evaluator.get_layer(@user, 'not_a_layer')
    assert_equal("Uninitialized", result.evaluation_details.reason)
    assert_equal(0, result.evaluation_details.config_sync_time)
  end

  def test_unrecognized
    result = @evaluator.check_gate(@user, 'not_a_gate')
    assert_equal("Unrecognized", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)

    result = @evaluator.get_config(@user, 'not_a_config')
    assert_equal("Unrecognized", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)

    result = @evaluator.get_layer(@user, 'not_a_layer')
    assert_equal("Unrecognized", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)
  end

  def test_network
    result = @evaluator.check_gate(@user, 'always_on_gate')
    assert_equal("Network", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)

    result = @evaluator.get_config(@user, 'sample_experiment')
    assert_equal("Network", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)

    result = @evaluator.get_layer(@user, 'a_layer')
    assert_equal("Network", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)
  end

  def test_local_override
    @evaluator.override_gate('always_on_gate', false)
    result = @evaluator.check_gate(@user, 'always_on_gate')
    assert_equal("LocalOverride", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)

    @evaluator.override_config('sample_experiment', { })
    result = @evaluator.get_config(@user, 'sample_experiment')
    assert_equal("LocalOverride", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)
  end

  def test_local_bootstrap
    options = StatsigOptions.new(bootstrap_values: @json_file, local_mode: true)
    bootstrap_driver = StatsigDriver.new('secret-key', options)
    boostrap_evaluator = bootstrap_driver.instance_variable_get('@evaluator')

    result = boostrap_evaluator.check_gate(@user, 'always_on_gate')
    assert_equal("Bootstrap", result.evaluation_details.reason)
    assert_equal($expected_sync_time, result.evaluation_details.config_sync_time)
    assert_equal(true, result.gate_value)
  end
end