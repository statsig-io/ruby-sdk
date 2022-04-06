require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'dynamic_config'
require 'layer'

class LayerExposureTest < Minitest::Test
  json_file = File.read("#{__dir__}/layer_exposure_download_config_specs.json")
  @@mock_response = JSON.parse(json_file).to_json

  def before_setup
    super
    stub_request(:post, 'https://api.statsig.com/v1/download_config_specs').to_return(status: 200, body: @@mock_response)
    stub_request(:post, 'https://api.statsig.com/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://api.statsig.com/v1/get_id_lists').to_return(status: 200)
    @user = StatsigUser.new({'userID' => 'random'})
  end

  def setup
    WebMock.enable!
  end

  def test_does_not_log_on_get_layer
    driver = StatsigDriver.new('secret-testcase')
    driver.get_layer(@user, 'unallocated_layer')
    driver.shutdown

    assert_requested(
      :post,
      'https://api.statsig.com/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'eventName' => 'statsig::layer_exposure',
            ),
        ]),
      :times => 0)
  end

  def test_does_not_log_on_non_existent_keys
    driver = StatsigDriver.new('secret-testcase')
    layer = driver.get_layer(@user, 'unallocated_layer')
    layer.get('a_string', 'err')
    driver.shutdown

    assert_requested(
      :post,
      'https://api.statsig.com/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'eventName' => 'statsig::layer_exposure',
            ),
        ]),
      :times => 0)
  end

  def test_unallocated_layer_logging
    driver = StatsigDriver.new('secret-testcase')
    layer = driver.get_layer(@user, 'unallocated_layer')
    layer.get("an_int", 0)
    driver.shutdown

    assert_requested(
      :post,
      'https://api.statsig.com/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'metadata' => {
              'config' => 'unallocated_layer',
              'ruleID' => 'default',
              'allocatedExperiment' => '',
              'parameterName' => 'an_int',
              'isExplicitParameter' => 'false'
            },
            ),
        ]),
      :times => 1)
  end

  def test_explicit_vs_implicit_parameter_logging
    driver = StatsigDriver.new('secret-testcase')
    layer = driver.get_layer(@user, 'explicit_vs_implicit_parameter_layer')
    layer.get("an_int", 0)
    layer.get("a_string", 'err')
    driver.shutdown

    assert_requested(
      :post,
      'https://api.statsig.com/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'metadata' => {
              'config' => 'explicit_vs_implicit_parameter_layer',
              'ruleID' => 'alwaysPass',
              'allocatedExperiment' => 'experiment',
              'parameterName' => 'an_int',
              'isExplicitParameter' => 'true'
            },
          ),
          hash_including(
            'metadata' => {
              'config' => 'explicit_vs_implicit_parameter_layer',
              'ruleID' => 'alwaysPass',
              'allocatedExperiment' => '',
              'parameterName' => 'a_string',
              'isExplicitParameter' => 'false'
            },
          ),
        ]),
      :times => 1)
  end

  def test_logs_user_and_event_name
    driver = StatsigDriver.new('secret-testcase')
    user = StatsigUser.new({'userID' => 'dloomb', 'email' => 'dan@loomb.com'})
    layer = driver.get_layer(user, 'unallocated_layer')
    layer.get("an_int", 0)
    driver.shutdown

    assert_requested(
      :post,
      'https://api.statsig.com/v1/log_event',
      :body => hash_including(
        'events' => [
          hash_including(
            'eventName' => 'statsig::layer_exposure',
            'user' => {
              'userID' => 'dloomb',
              'email' => 'dan@loomb.com',
            },
            ),
        ]),
      :times => 1)
  end

  def teardown
    super
    WebMock.disable!
  end
end