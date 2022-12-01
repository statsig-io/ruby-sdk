# typed: true
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'dynamic_config'
require 'layer'

class ManualExposureTest < Minitest::Test


  def before_setup
    super

    json_file = File.read("#{__dir__}/download_config_specs.json")
    @mock_response = JSON.parse(json_file).to_json

    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @user = StatsigUser.new({ 'userID' => 'random' })
    @options = StatsigOptions.new(disable_diagnostics_logging: true, local_mode: true)
  end

  def setup
    WebMock.enable!
  end

  def teardown
    super
    Statsig.shutdown
  end

  def test_api_with_exposure_logging_disabled
    Statsig.initialize('secret-testcase', @options)
    Statsig.check_gate_with_exposure_logging_disabled(@user, 'always_on_gate')
    Statsig.get_config_with_exposure_logging_disabled(@user, 'test_config')
    Statsig.get_experiment_with_exposure_logging_disabled(@user, 'sample_experiment')
    layer = Statsig.get_layer_with_exposure_logging_disabled(@user, 'a_layer')
    layer.get('experiment_param', '')

    driver = Statsig.instance_variable_get('@shared_instance')
    net = driver.instance_variable_get('@net')
    spy = Spy.on(net, :post_logs).and_return

    logger = driver.instance_variable_get('@logger')
    Spy.on(logger, :flush_async).and_return do
      # fail the test if shutting down does async flush - should be sync
      assert_equal(true, false)
    end
    logger.shutdown

    assert_nil(spy.calls[0]) # no events logged
  end

  def test_manual_exposure_logging
    Statsig.initialize('secret-testcase', @options)
    Statsig.manually_log_gate_exposure(@user, 'always_on_gate')
    Statsig.manually_log_config_exposure(@user, 'test_config')
    Statsig.manually_log_experiment_exposure(@user, 'sample_experiment')
    Statsig.manually_log_layer_parameter_exposure(@user, 'a_layer', 'experiment_param')

    driver = Statsig.instance_variable_get('@shared_instance')
    net = driver.instance_variable_get('@net')
    spy = Spy.on(net, :post_logs).and_return

    logger = driver.instance_variable_get('@logger')
    Spy.on(logger, :flush_async).and_return do
      # fail the test if shutting down does async flush - should be sync
      assert_equal(true, false)
    end
    logger.shutdown

    events = spy.calls[0].args[0]
    assert_instance_of(Array, events)
    assert_equal(4, events.size)
  end
end