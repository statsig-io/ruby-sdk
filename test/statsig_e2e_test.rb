# typed: false
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
$expected_sync_time = 1631638014811

class StatsigE2ETest < Minitest::Test
  @@json_file = File.read("#{__dir__}/data/download_config_specs.json")
  @@mock_response = JSON.parse(@@json_file).to_json

  def before_setup
    super
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @@mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @statsig_user = StatsigUser.new({ 'userID' => '123', 'email' => 'testuser@statsig.com' })
    @random_user = StatsigUser.new({ 'userID' => 'random' })
  end

  def setup
    WebMock.enable!
  end

  def test_feature_gate
    driver = StatsigDriver.new('secret-testcase', nil, (-> (e) {
      # error callback should not be called on successful initialize
      assert(false)
    }))
    assert(driver.check_gate(@statsig_user, 'always_on_gate') == true)
    assert(driver.check_gate(@statsig_user, 'on_for_statsig_email') == true)
    assert(driver.check_gate(@statsig_user, 'email_not_null') == true)
    assert(driver.check_gate(@random_user, 'on_for_statsig_email') == false)
    assert(driver.check_gate(@random_user, 'email_not_null') == false)
    driver.shutdown
    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including('eventName' => 'statsig::diagnostics'),
          hash_including(
            'eventName' => 'statsig::gate_exposure',
            'user' => {
              'userID' => '123',
              'email' => 'testuser@statsig.com'
            },
            'metadata' => hash_including(
              'gate' => 'always_on_gate',
              'gateValue' => 'true',
              'ruleID' => '6N6Z8ODekNYZ7F8gFdoLP5'
            )),
          hash_including(
            'eventName' => 'statsig::gate_exposure',
            'metadata' => hash_including(
              'gate' => 'on_for_statsig_email',
              'gateValue' => 'true',
              'ruleID' => '7w9rbTSffLT89pxqpyhuqK'
            )),
          hash_including(
            'eventName' => 'statsig::gate_exposure',
            'metadata' => hash_including(
              'gate' => 'email_not_null',
              'gateValue' => 'true',
              'ruleID' => '7w9rbTSffLT89pxqpyhuqK'
            )),
          hash_including(
            'eventName' => 'statsig::gate_exposure',
            'user' => {
              'userID' => 'random'
            },
            'metadata' => hash_including(
              'gate' => 'on_for_statsig_email',
              'gateValue' => 'false',
              'ruleID' => 'default'
            )),
          hash_including(
            'eventName' => 'statsig::gate_exposure',
            'metadata' => hash_including(
              'gate' => 'email_not_null',
              'gateValue' => 'false',
              'ruleID' => 'default'
            )),
        ],
        'statsigMetadata' =>
          Statsig.get_statsig_metadata
      ),
      :times => 1)
  end

  def test_dynamic_config
    driver = StatsigDriver.new('secret-testcase')
    config = driver.get_config(@statsig_user, 'test_config')
    assert(config.get('number', 0) == 7)
    assert(config.get('string', '') == 'statsig')
    assert(config.get('boolean', true) == false)

    config = driver.get_config(@random_user, 'test_config')
    assert(config.get('number', 0) == 4)
    assert(config.get('string', '') == 'default')
    assert(config.get('boolean', false) == true)
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including('eventName' => 'statsig::diagnostics'),
          hash_including(
            'eventName' => 'statsig::config_exposure',
            'metadata' => hash_including(
              'config' => 'test_config',
              'ruleID' => '1kNmlB23wylPFZi1M0Divl'
            )),
          hash_including(
            'eventName' => 'statsig::config_exposure',
            'metadata' => hash_including(
              'config' => 'test_config',
              'ruleID' => 'default'
            )),
        ]),
      :times => 1)
  end

  def test_experiment
    driver = StatsigDriver.new('secret-testcase')
    experiment = driver.get_experiment(@random_user, 'sample_experiment')
    assert(experiment.get('experiment_param', '') == 'control')

    experiment = driver.get_experiment(@statsig_user, 'sample_experiment')
    assert(experiment.get('experiment_param', '') == 'test')

    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including('eventName' => 'statsig::diagnostics'),
          hash_including(
            'eventName' => 'statsig::config_exposure',
            'metadata' => hash_including(
              'config' => 'sample_experiment',
              'ruleID' => '2RamGsERWbWMIMnSfOlQuX'
            )),
          hash_including(
            'eventName' => 'statsig::config_exposure',
            'metadata' => hash_including(
              'config' => 'sample_experiment',
              'ruleID' => '2RamGujUou6h2bVNQWhtNZ'
            )),
        ]),
      :times => 1)
  end

  def test_log_event
    driver = StatsigDriver.new('secret-testcase')
    driver.log_event(@random_user, 'add_to_cart', 'SKU_12345', { 'price' => '9.99', 'item_name' => 'diet_coke_48_pack' })
    driver.shutdown

    assert_requested(
      :post,
      'https://statsigapi.net/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including('eventName' => 'statsig::diagnostics'),
          hash_including(
            'eventName' => 'add_to_cart',
            'value' => 'SKU_12345',
            'metadata' => {
              'price' => '9.99',
              'item_name' => 'diet_coke_48_pack'
            },
            'user' => hash_including(
              'userID' => "random"
            )
          ),
        ]),
      :times => 1)
  end

  def test_bootstrap_option
    # in local mode (without network), bootstrap_values makes evaluation work
    options = StatsigOptions.new(bootstrap_values: @@json_file, local_mode: true)
    driver = StatsigDriver.new('secret-testcase', options)
    assert_equal(driver.check_gate(StatsigUser.new({ 'userID' => 'jkw' }), 'always_on_gate'), true)

    # with network, rules_updated_callback gets called when there are updated rulesets coming back from server
    callback_validated = false
    options = StatsigOptions.new(rulesets_sync_interval: 0.1, rules_updated_callback: ->(rules, time) {
      if rules == @@mock_response && time == 1631638014811
        callback_validated = true
      end
    })
    driver = StatsigDriver.new('secret-testcase', options)
    assert_equal(driver.check_gate(StatsigUser.new({ 'userID' => 'jkw' }), 'always_on_gate'), true)
    assert_equal(true, callback_validated)
    driver.shutdown
  end

  def teardown
    super
    WebMock.disable!
  end
end