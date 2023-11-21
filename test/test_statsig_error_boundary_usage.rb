require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class StatsigErrorBoundaryUsageTest < BaseTest
  suite :StatsigErrorBoundaryUsageTest
  def before_setup
    super
    stub_request(:post, 'https://statsigapi.net/v1/sdk_exception').to_return(status: 200)
    stub_download_config_specs.to_return(status: 500)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 500)
  end

  def setup
    super
    WebMock.enable!
    @driver = StatsigDriver.new(
      'secret-key',
      StatsigOptions.new(
        rulesets_sync_interval: 0.5,
        idlists_sync_interval: 0.5,
        logging_interval_seconds: 0.5,
        disable_diagnostics_logging: true
      )
    )
    @evaluator = @driver.instance_variable_get('@evaluator')
    @logger = @driver.instance_variable_get('@logger')
    @store = @evaluator.instance_variable_get('@spec_store')
    @user = StatsigUser.new({ 'userID' => 'dloomb' })
  end

  def mock_api_raises(base_class, api)
    Spy.on(base_class, api).and_raise(RuntimeError, "exception thrown from '#{api}'")
  end

  def teardown
    super
    Spy.teardown
    @driver.shutdown
    WebMock.reset!
    WebMock.disable!
  end

  def test_errors_with_check_gate
    mock_api_raises(@evaluator, :check_gate)
    res = @driver.check_gate(@user, 'a_gate')
    assert_equal(false, res)
    assert_exception('RuntimeError', "exception thrown from 'check_gate'")
  end

  def test_errors_with_get_config
    mock_api_raises(@evaluator, :get_config)
    res = @driver.get_config(@user, 'a_config')
    assert_instance_of(DynamicConfig, res)
    assert_exception('RuntimeError', "exception thrown from 'get_config'")
  end

  def test_errs_with_get_experiment
    mock_api_raises(@evaluator, :get_config)
    res = @driver.get_experiment(@user, 'an_experiment')
    assert_instance_of(DynamicConfig, res)
    assert_exception('RuntimeError', "exception thrown from 'get_config'")
  end

  def test_errors_with_get_layer
    mock_api_raises(@evaluator, :get_layer)
    res = @driver.get_layer(@user, 'a_layer')
    assert_instance_of(Layer, res)
    assert_exception('RuntimeError', "exception thrown from 'get_layer'")
  end

  def test_errors_with_log_event
    mock_api_raises(@logger, :log_event)
    @driver.log_event(@user, 'an_event')
    assert_exception('RuntimeError', "exception thrown from 'log_event'")
  end

  def test_errors_with_periodic_flush
    spy = mock_api_raises(@logger, :flush_async)
    wait_for(timeout: 1) do
      spy.has_been_called?
    end
    assert_exception('RuntimeError', "exception thrown from 'flush_async'")
  end

  def test_errors_with_rulesets_sync
    spy = mock_api_raises(@store, :download_config_specs)
    wait_for(timeout: 1) do
      spy.has_been_called?
    end
    assert_exception('RuntimeError', "exception thrown from 'download_config_specs'")
  end

  def test_errors_with_idlist_sync
    spy = mock_api_raises(@store, :get_id_lists_from_network)
    wait_for(timeout: 1) do
      spy.has_been_called?
    end
    assert_exception('RuntimeError', "exception thrown from 'get_id_lists_from_network'")
  end

  def test_errors_with_initialize
    opts = MiniTest::Mock.new
    (0..1).each {
      opts.expect(:is_a?, true, [StatsigOptions])
    }
    (0..3).each {
      opts.expect(:nil?, false)
    }

    opts.expect(:instance_of?, true, [StatsigOptions])

    StatsigDriver.new('secret-key', opts)
    assert_exception('MockExpectationError', 'method_missing')
  end

  def test_errors_with_shutdown
    mock_api_raises(@evaluator, :shutdown)
    @driver.shutdown
    assert_exception('RuntimeError', "exception thrown from 'shutdown'")
  end

  private

  def assert_exception(type, trace)
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1) do |req|
      body = JSON.parse(req.body)
      assert_equal(type, body['exception'])
      assert(body['info'].include?(trace), "#{body["info"]} did not include #{trace}")
    end
  end

end