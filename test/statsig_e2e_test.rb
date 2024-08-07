require_relative 'test_helper'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'dynamic_config'
require 'layer'

# There are 2 mock gates, 1 mock config, and 1 mock experiment
# always_on_gate has a single group, Everyone 100%
# on_for_statsig_email has a single group, email contains "@statsig.com" 100%
# test_config has a single group, email contains "@statsig.com" 100%
# - passing returns {number: 7, string: "statsig", boolean: false}
# - failing (default) returns {number: 4, string: "default", boolean: true}
# sample_experiment is a 50/50 experiment with a single parameter, experiment_param
# - ("test" or "control" depending on the user's group)
$expected_sync_time = 1_631_638_014_811

class StatsigE2ETest < BaseTest
  suite :StatsigE2ETest
  @@json_file = File.read("#{__dir__}/data/download_config_specs.json")
  @@mock_response = JSON.parse(@@json_file).to_json

  def before_setup
    super
    stub_download_config_specs.to_return(status: 200, body: @@mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @statsig_user = StatsigUser.new({ 'userID' => '123', 'email' => 'testuser@statsig.com' })
    @random_user = StatsigUser.new({ 'userID' => 'random' })
    @options = StatsigOptions.new(disable_diagnostics_logging: true)
  end

  def setup
    super
    WebMock.enable!
    @events = []
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200, body: lambda { |request|
      gz = Zlib::GzipReader.new(StringIO.new(request.body))
      parsedBody = gz.read
      gz.close
      @events.push(*JSON.parse(parsedBody)['events'])
      return ''
    })
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_get_feature_gate
    driver = StatsigDriver.new(
      SDK_KEY,
      @options,
      lambda { |_e|
        # error callback should not be called on successful initialize
        assert(false)
      }
    )
    gate_without_evaluation = driver.get_gate(@statsig_user, 'always_on_gate',
                                              Statsig::GetGateOptions.new(skip_evaluation: true))
    gate_with_evaluation = driver.get_gate(@statsig_user, 'always_on_gate')
    assert_equal('always_on_gate', gate_without_evaluation.name)
    assert_equal(false, gate_without_evaluation.value)
    assert_equal(true, gate_with_evaluation.value)
    driver.shutdown
  end

  def test_check_feature_gate
    driver = StatsigDriver.new(
      SDK_KEY,
      @options,
      lambda { |_e|
        # error callback should not be called on successful initialize
        assert(false)
      }
    )
    assert(driver.check_gate(@statsig_user, 'always_on_gate') == true)
    assert(driver.check_gate(@statsig_user, 'on_for_statsig_email') == true)
    assert(driver.check_gate(@statsig_user, 'email_not_null') == true)
    assert(driver.check_gate(@random_user, 'on_for_statsig_email') == false)
    assert(driver.check_gate(@random_user, 'email_not_null') == false)
    driver.shutdown

    assert_equal(5, @events.length)
    event = @events[0]
    assert_equal('statsig::gate_exposure', event['eventName'])
    assert_equal('always_on_gate', event['metadata']['gate'])
    assert_equal('6N6Z8ODekNYZ7F8gFdoLP5', event['metadata']['ruleID'])
    assert_equal('true', event['metadata']['gateValue'])
    assert_equal('123', event['user']['userID'])
    assert_equal('testuser@statsig.com', event['user']['email'])

    event = @events[1]
    assert_equal('statsig::gate_exposure', event['eventName'])
    assert_equal('on_for_statsig_email', event['metadata']['gate'])
    assert_equal('7w9rbTSffLT89pxqpyhuqK', event['metadata']['ruleID'])
    assert_equal('true', event['metadata']['gateValue'])

    event = @events[2]
    assert_equal('statsig::gate_exposure', event['eventName'])
    assert_equal('email_not_null', event['metadata']['gate'])
    assert_equal('7w9rbTSffLT89pxqpyhuqK', event['metadata']['ruleID'])
    assert_equal('true', event['metadata']['gateValue'])

    event = @events[3]
    assert_equal('statsig::gate_exposure', event['eventName'])
    assert_equal('on_for_statsig_email', event['metadata']['gate'])
    assert_equal('default', event['metadata']['ruleID'])
    assert_equal('false', event['metadata']['gateValue'])
    assert_equal('random', event['user']['userID'])

    event = @events[4]
    assert_equal('statsig::gate_exposure', event['eventName'])
    assert_equal('email_not_null', event['metadata']['gate'])
    assert_equal('default', event['metadata']['ruleID'])
    assert_equal('false', event['metadata']['gateValue'])
  end

  def test_dynamic_config
    driver = StatsigDriver.new(SDK_KEY, @options)
    config = driver.get_config(@statsig_user, 'test_config')
    assert(config.group_name == 'statsig email')
    assert(config.id_type == 'anonymousID')
    assert(config.get('number', 0) == 7)
    assert(config.get('string', '') == 'statsig')
    assert(config.get('boolean', true) == false)

    config = driver.get_config(@random_user, 'test_config')
    assert_nil(config.group_name)
    assert(config.id_type == 'anonymousID')
    assert(config.get('number', 0) == 4)
    assert(config.get('string', '') == 'default')
    assert(config.get('boolean', false) == true)
    driver.shutdown

    assert_equal(2, @events.length)
    event = @events[0]
    assert_equal('statsig::config_exposure', event['eventName'])
    assert_equal('test_config', event['metadata']['config'])
    assert_equal('1kNmlB23wylPFZi1M0Divl', event['metadata']['ruleID'])

    event = @events[1]
    assert_equal('statsig::config_exposure', event['eventName'])
    assert_equal('test_config', event['metadata']['config'])
    assert_equal('default', event['metadata']['ruleID'])
  end

  def test_experiment
    driver = StatsigDriver.new(SDK_KEY, @options)
    experiment = driver.get_experiment(@random_user, 'sample_experiment')
    assert(experiment.get('experiment_param', '') == 'control')
    assert(experiment.group_name == 'Control')
    assert(experiment.id_type == 'userID')

    experiment = driver.get_experiment(@statsig_user, 'sample_experiment')
    assert(experiment.get('experiment_param', '') == 'test')
    assert(experiment.group_name == 'Test')
    assert(experiment.id_type == 'userID')

    driver.shutdown

    assert_equal(2, @events.length)
    event = @events[0]
    assert_equal('statsig::config_exposure', event['eventName'])
    assert_equal('sample_experiment', event['metadata']['config'])
    assert_equal('2RamGsERWbWMIMnSfOlQuX', event['metadata']['ruleID'])

    event = @events[1]
    assert_equal('statsig::config_exposure', event['eventName'])
    assert_equal('sample_experiment', event['metadata']['config'])
    assert_equal('2RamGujUou6h2bVNQWhtNZ', event['metadata']['ruleID'])
  end

  def test_log_event
    driver = StatsigDriver.new(SDK_KEY, @options)
    driver.log_event(@random_user, 'add_to_cart', 'SKU_12345',
                     { 'price' => '9.99', 'item_name' => 'diet_coke_48_pack' })
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('add_to_cart', event['eventName'])
    assert_equal('SKU_12345', event['value'])
    assert_equal('9.99', event['metadata']['price'])
    assert_equal('diet_coke_48_pack', event['metadata']['item_name'])
    assert_equal('random', event['user']['userID'])
  end

  def test_bootstrap_option
    # in local mode (without network), bootstrap_values makes evaluation work
    options = StatsigOptions.new(bootstrap_values: @@json_file, local_mode: true)
    driver = StatsigDriver.new(SDK_KEY, options)
    assert_equal(driver.check_gate(StatsigUser.new({ 'userID' => 'jkw' }), 'always_on_gate'), true)

    # with network, rules_updated_callback gets called when there are updated rulesets coming back from server
    callback_validated = false
    options = StatsigOptions.new(rulesets_sync_interval: 0.1, rules_updated_callback: lambda { |rules, time|
      if rules == @@mock_response && time == 1_631_638_014_811
        callback_validated = true
      end
    })
    driver = StatsigDriver.new(SDK_KEY, options)
    assert_equal(driver.check_gate(StatsigUser.new({ 'userID' => 'jkw' }), 'always_on_gate'), true)
    assert_equal(true, callback_validated)
    driver.shutdown
  end
end
