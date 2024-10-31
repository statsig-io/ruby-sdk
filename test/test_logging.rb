require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'layer'
require 'webmock/minitest'

class TestLogging < BaseTest
  suite :TestLogging

  def setup
    super
    WebMock.enable!
    @error_boundary = Statsig::ErrorBoundary.new(SDK_KEY, StatsigOptions.new)
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_event_does_not_have_private_attributes
    user = StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret_value' => 'shhhhh' } })
    event = StatsigEvent.new('test')
    event.user = user
    assert(event.user['private_attributes'] == nil)
    assert(event.serialize.has_key?('privateAttributes') == false)
  end

  def test_retrying_failed_logs
    stub_request(:post, 'https://test_retrying_failed_logs.net/v1/log_event').to_return(status: 500)
    stub_download_config_specs('https://test_retrying_failed_logs.net/v2').to_return(status: 500)
    stub_request(:post, 'https://test_retrying_failed_logs.net/v1/get_id_lists').to_return(status: 200)
    codes = []
    WebMock.after_request do |req, res|
      if req.uri.to_s.end_with? 'log_event'
        codes.push(res.status[0])
        stub_request(:post, 'https://test_retrying_failed_logs.net/v1/log_event').to_return(status: 202)
      end
    end

    options = StatsigOptions.new(
      nil,
      download_config_specs_url: 'https://test_retrying_failed_logs.net/v2/download_config_specs',
      log_event_url: 'https://test_retrying_failed_logs.net/v1/log_event',
      get_id_lists_url: 'https://test_retrying_failed_logs.net/v1/get_id_lists',
      local_mode: false
    )
    net = Statsig::Network.new(SDK_KEY, options)
    logger = Statsig::StatsigLogger.new(net, StatsigOptions.new, @error_boundary)
    logger.log_event(StatsigEvent.new('my_event'))

    Spy.on(logger, :flush_async).and_return do
      # fail the test if flush does async flush - should be sync
      assert_equal(true, false)
    end
    logger.flush

    assert_equal([500, 202], codes)
    assert_equal(0, logger.instance_variable_get('@events').length)
    logger.shutdown
  end

  def test_non_blocking_log
    stub_request(:post, 'https://test_non_blocking_log.net/v1/log_event').to_return(status: 500)
    stub_download_config_specs('https://test_non_blocking_log.net/v2').to_return(status: 500)
    stub_request(:post, 'https://test_non_blocking_log.net/v1/get_id_lists').to_return(status: 200)

    options = StatsigOptions.new(
      nil,
      download_config_specs_url: 'https://test_non_blocking_log.net/v2/download_config_specs',
      log_event_url: 'https://test_non_blocking_log.net/v1/log_event',
      get_id_lists_url: 'https://test_non_blocking_log.net/v1/get_id_lists',
      local_mode: false
    )
    net = Statsig::Network.new(SDK_KEY, options)
    logger = Statsig::StatsigLogger.new(net, StatsigOptions.new(logging_max_buffer_size: 2), @error_boundary)

    called = false
    called_after_wait = false
    Spy.on(net, :post_logs).and_return do |req, &block|
      called = true
      sleep 5
      called_after_wait = true
    end

    logger.log_event(StatsigEvent.new('my_event'))
    logger.log_event(StatsigEvent.new('my_other_event'))

    wait_for(timeout: 1) do
      called == true
    end

    assert_equal(true, called)
    assert_equal(false, called_after_wait)
    logger.shutdown
  end

  def test_exposure_event
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200, body: 'hello')
    stub_download_config_specs.to_return(status: 500)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 500)

    options = StatsigOptions.new(
      nil,
      download_config_specs_url: 'https://statsigapi.net/v2/download_config_specs',
      log_event_url: 'https://statsigapi.net/v1/log_event',
      get_id_lists_url: 'https://statsigapi.net/v1/get_id_lists',
      local_mode: true
    )
    net = Statsig::Network.new(SDK_KEY, options)
    spy = Spy.on(net, :post_logs).and_return
    @statsig_metadata = {
      'sdkType' => 'ruby-server',
      'sdkVersion' => Gem::Specification::load('statsig.gemspec')&.version,
    }

    unrecognized_eval = Statsig::EvaluationDetails.unrecognized(1, 2)
    override_eval = Statsig::EvaluationDetails.local_override(3, 4)
    network_eval = Statsig::EvaluationDetails.network(5, 6)

    logger = Statsig::StatsigLogger.new(net, StatsigOptions.new, @error_boundary)

    logger.log_gate_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' } }),
      Statsig::ConfigResult.new(
        name: 'test_gate',
        gate_value: true,
        rule_id: 'gate_rule_id',
        secondary_exposures: [{
          'gate' => 'another_gate',
          'gateValue' => 'true',
          'ruleID' => 'another_rule_id'
        }],
        evaluation_details: unrecognized_eval
      ),
      { :is_manual_exposure => true },
    )

    logger.log_config_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' } }),
      Statsig::ConfigResult.new(
        name: 'test_config',
        gate_value: true,
        rule_id: 'config_rule_id',
        secondary_exposures: [{
          'gate' => 'another_gate_2',
          'gateValue' => 'false',
          'ruleID' => 'another_rule_id_2'
        }],
        evaluation_details: override_eval
      ),
      { :is_manual_exposure => false },
    )

    logger.log_layer_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' } }),
      Layer.new('test_layer', { 'foo' => 1 }, 'layer_rule_id'),
      'test_parameter',
      Statsig::ConfigResult.new(name: 'test_layer', evaluation_details: network_eval)
    )

    Spy.on(logger, :flush_async).and_return do
      # fail the test if shutting down does async flush - should be sync
      assert_equal(true, false)
    end
    logger.shutdown

    events = spy.calls[0].args[0]
    assert_instance_of(Array, events)
    assert_equal(3, events.size)

    gate_exposure = JSON.parse(JSON.generate(events[0]))
    assert(gate_exposure['eventName'] == 'statsig::gate_exposure')
    assert_equal(
      {
        'gate' => 'test_gate',
        'gateValue' => 'true',
        'ruleID' => 'gate_rule_id',
        'reason' => 'Unrecognized',
        'configSyncTime' => unrecognized_eval.config_sync_time,
        'initTime' => unrecognized_eval.init_time,
        'serverTime' => unrecognized_eval.server_time,
        'isManualExposure' => 'true',
      }, gate_exposure['metadata'])
    assert(gate_exposure['user']['userID'] == '123')
    assert(gate_exposure['user']['privateAttributes'] == nil)
    assert_equal(
      [{
         'gate' => 'another_gate',
         'gateValue' => 'true',
         'ruleID' => 'another_rule_id'
       }], gate_exposure['secondaryExposures'])

    config_exposure = JSON.parse(JSON.generate(events[1]))
    assert(config_exposure['eventName'] == 'statsig::config_exposure')
    assert_equal(
      {
        'config' => 'test_config', 'ruleID' => 'config_rule_id',
        'reason' => 'LocalOverride',
        'configSyncTime' => override_eval.config_sync_time,
        'initTime' => override_eval.init_time,
        'serverTime' => override_eval.server_time,
        'rulePassed' => 'true',
      }, config_exposure['metadata'])
    assert(config_exposure['user']['userID'] == '123')
    assert(config_exposure['user']['privateAttributes'] == nil)
    assert_equal(
      [{
         'gate' => 'another_gate_2',
         'gateValue' => 'false',
         'ruleID' => 'another_rule_id_2'
       }],
      config_exposure['secondaryExposures'])

    layer_exposure = JSON.parse(JSON.generate(events[2]))
    assert_equal('statsig::layer_exposure', layer_exposure['eventName'])
    assert_equal(
      {
        'config' => 'test_layer',
        'ruleID' => 'layer_rule_id',
        'allocatedExperiment' => '',
        'parameterName' => 'test_parameter',
        'isExplicitParameter' => 'false',
        'reason' => 'Network',
        'configSyncTime' => network_eval.config_sync_time,
        'initTime' => network_eval.init_time,
        'serverTime' => network_eval.server_time,
      }, layer_exposure['metadata'])
    assert(layer_exposure['user']['userID'] == '123')
    assert(layer_exposure['user']['privateAttributes'] == nil)
    logger.shutdown
  end
end
