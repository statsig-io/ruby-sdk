require 'minitest'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'layer'
require 'webmock/minitest'

class TestLogging < Minitest::Test
  def setup
    WebMock.enable!
  end

  def teardown
    super
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
    stub_request(:post, "https://test_retrying_failed_logs.net/v1/log_event").to_return(status: 500)
    codes = []
    WebMock.after_request do |req, res|
      if req.uri.to_s.end_with? "log_event"
        codes.push(res.status[0])
        stub_request(:post, "https://test_retrying_failed_logs.net/v1/log_event").to_return(status: 202)
      end
    end

    net = Statsig::Network.new('secret-abc', 'https://test_retrying_failed_logs.net/v1/', false)
    logger = Statsig::StatsigLogger.new(net, StatsigOptions.new)
    logger.log_event(StatsigEvent.new("my_event"))

    logger.flush

    assert_equal([500, 202], codes)
    assert_equal(0, logger.instance_variable_get("@events").length)
  end

  def test_non_blocking_log
    stub_request(:post, "https://test_non_blocking_log.net/v1/log_event").to_return(status: 500)

    net = Statsig::Network.new('secret-abc', 'https://test_non_blocking_log.net/v1/', false)
    logger = Statsig::StatsigLogger.new(net, StatsigOptions.new(logging_max_buffer_size: 2))

    called = false
    called_after_wait = false
    Spy.on(net, :post_logs).and_return do |req, &block|
      called = true
      sleep 5
      called_after_wait = true
    end

    logger.log_event(StatsigEvent.new("my_event"))
    logger.log_event(StatsigEvent.new("my_other_event"))

    sleep 0.1
    assert_equal(true, called)
    assert_equal(false, called_after_wait)
  end

  def test_exposure_event
    stub_request(:post, "https://statsigapi.net/v1/log_event").to_return(status: 200, body: "hello")
    stub_request(:post, "https://statsigapi.net/v1/download_config_specs").to_return(status: 500)
    stub_request(:post, "https://statsigapi.net/v1/get_id_lists").to_return(status: 500)

    net = Statsig::Network.new('secret-abc', 'https://statsigapi.net/v1/', 1)
    spy = Spy.on(net, :post_logs).and_return
    @statsig_metadata = {
      'sdkType' => 'ruby-server',
      'sdkVersion' => Gem::Specification::load('statsig.gemspec')&.version,
    }

    unrecognized_eval = Statsig::EvaluationDetails.unrecognized(1, 2)
    override_eval = Statsig::EvaluationDetails.local_override(3, 4)
    network_eval = Statsig::EvaluationDetails.network(5, 6)

    logger = Statsig::StatsigLogger.new(net, StatsigOptions.new)
    logger.log_gate_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' } }),
      'test_gate',
      true,
      'gate_rule_id',
      [{
         "gate" => 'another_gate',
         "gateValue" => "true",
         "ruleID" => 'another_rule_id'
       }],
      unrecognized_eval
    )

    logger.log_config_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' } }),
      'test_config',
      'config_rule_id',
      [{
         "gate" => 'another_gate_2',
         "gateValue" => "false",
         "ruleID" => 'another_rule_id_2'
       }],
      override_eval
    )

    logger.log_layer_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' } }),
      Layer.new('test_layer', { 'foo' => 1 }, 'layer_rule_id'),
      'test_parameter',
      Statsig::ConfigResult.new('test_layer', evaluation_details: network_eval)
    )

    logger.flush

    events = spy.calls[0].args[0]
    assert_instance_of(Array, events)
    assert_equal(3, events.size)

    gate_exposure = events[0]
    assert(gate_exposure['eventName'] == 'statsig::gate_exposure')
    assert_equal(
      {
        "gate" => "test_gate",
        "gateValue" => "true",
        "ruleID" => "gate_rule_id",
        "reason" => "Unrecognized",
        "configSyncTime" => unrecognized_eval.config_sync_time,
        'initTime' => unrecognized_eval.init_time,
        'serverTime' => unrecognized_eval.server_time,
      }, gate_exposure['metadata'])
    assert(gate_exposure['user']['userID'] == '123')
    assert(gate_exposure['user']['privateAttributes'] == nil)
    assert_equal(
      [{
         "gate" => 'another_gate',
         "gateValue" => "true",
         "ruleID" => 'another_rule_id'
       }], gate_exposure['secondaryExposures'])

    config_exposure = events[1]
    assert(config_exposure['eventName'] == 'statsig::config_exposure')
    assert_equal(
      {
        "config" => "test_config", "ruleID" => "config_rule_id",
        "reason" => "LocalOverride",
        "configSyncTime" => override_eval.config_sync_time,
        'initTime' => override_eval.init_time,
        'serverTime' => override_eval.server_time
      }, config_exposure['metadata'])
    assert(config_exposure['user']['userID'] == '123')
    assert(config_exposure['user']['privateAttributes'] == nil)
    assert_equal(
      [{
         "gate" => 'another_gate_2',
         "gateValue" => "false",
         "ruleID" => 'another_rule_id_2'
       }],
      config_exposure['secondaryExposures'])

    layer_exposure = events[2]
    assert_equal('statsig::layer_exposure', layer_exposure['eventName'])
    assert_equal(
      {
        "config" => "test_layer",
        "ruleID" => "layer_rule_id",
        "allocatedExperiment" => "",
        "parameterName" => "test_parameter",
        "isExplicitParameter" => "false",
        "reason" => "Network",
        "configSyncTime" => network_eval.config_sync_time,
        'initTime' => network_eval.init_time,
        'serverTime' => network_eval.server_time,
      }, layer_exposure['metadata'])
    assert(layer_exposure['user']['userID'] == '123')
    assert(layer_exposure['user']['privateAttributes'] == nil)

  end
end