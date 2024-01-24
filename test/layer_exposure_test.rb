

require_relative 'test_helper'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'dynamic_config'
require 'layer'

class LayerExposureTest < BaseTest
  suite :LayerExposureTest

  def before_setup
    super

    json_file = File.read("#{__dir__}/data/layer_exposure_download_config_specs.json")
    @mock_response = JSON.parse(json_file).to_json
    @options = StatsigOptions.new(disable_diagnostics_logging: true)

    stub_download_config_specs.to_return(status: 200, body: @mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @user = StatsigUser.new({ 'userID' => 'random' })
  end

  def setup
    super
    WebMock.enable!
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_does_not_log_on_get_layer
    driver = StatsigDriver.new(SDK_KEY, @options)
    driver.get_layer(@user, 'unallocated_layer')
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'eventName' => 'statsig::layer_exposure',
          ),
        ]),
      :times => 0)
  end

  def test_does_not_log_on_non_existent_keys
    driver = StatsigDriver.new(SDK_KEY, @options)
    layer = driver.get_layer(@user, 'unallocated_layer')
    layer.get('a_string', 'err')
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'eventName' => 'statsig::layer_exposure',
          ),
        ]),
      :times => 0)
  end

  def test_unallocated_layer_logging
    driver = StatsigDriver.new(SDK_KEY, @options)
    layer = driver.get_layer(@user, 'unallocated_layer')
    layer.get("an_int", 0)
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'metadata' => hash_including(
              'config' => 'unallocated_layer',
              'ruleID' => 'default',
              'allocatedExperiment' => '',
              'parameterName' => 'an_int',
              'isExplicitParameter' => 'false',
              'reason' => 'Network',
            ),
          ),
        ]),
      :times => 1)
  end

  def test_explicit_vs_implicit_parameter_logging
    driver = StatsigDriver.new(SDK_KEY, @options)
    layer = driver.get_layer(@user, 'explicit_vs_implicit_parameter_layer')
    layer.get("an_int", 0)
    layer.get("a_string", 'err')
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'metadata' => hash_including(
              'config' => 'explicit_vs_implicit_parameter_layer',
              'ruleID' => 'alwaysPass',
              'allocatedExperiment' => 'experiment',
              'parameterName' => 'an_int',
              'isExplicitParameter' => 'true',
              'reason' => 'Network'
            ),
          ),
          hash_including(
            'metadata' => hash_including(
              'config' => 'explicit_vs_implicit_parameter_layer',
              'ruleID' => 'alwaysPass',
              'allocatedExperiment' => '',
              'parameterName' => 'a_string',
              'isExplicitParameter' => 'false',
              'reason' => 'Network'
            ),
          ),
        ]),
      :times => 1)
  end

  def test_logs_user_and_event_name
    driver = StatsigDriver.new(SDK_KEY, @options)
    user = StatsigUser.new({ 'userID' => 'dloomb', 'email' => 'dan@loomb.com' })
    layer = driver.get_layer(user, 'unallocated_layer')
    layer.get("an_int", 0)
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        :events => [
          hash_including(
            :eventName => 'statsig::layer_exposure',
            :user => {
              :userID => 'dloomb',
              :email => 'dan@loomb.com',
            },
          ),
        ]),
      :times => 1)
  end
end