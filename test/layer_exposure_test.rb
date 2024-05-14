

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
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @user = StatsigUser.new({ 'userID' => 'random' })
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

  def test_does_not_log_on_get_layer
    driver = StatsigDriver.new(SDK_KEY, @options)
    driver.get_layer(@user, 'unallocated_layer')
    driver.shutdown

    assert_equal(0, @events.length)
  end

  def test_does_not_log_on_non_existent_keys
    driver = StatsigDriver.new(SDK_KEY, @options)
    layer = driver.get_layer(@user, 'unallocated_layer')
    layer.get('a_string', 'err')
    driver.shutdown

    assert_equal(0, @events.length)
  end

  def test_unallocated_layer_logging
    driver = StatsigDriver.new(SDK_KEY, @options)
    layer = driver.get_layer(@user, 'unallocated_layer')
    layer.get("an_int", 0)
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::layer_exposure', event['eventName'])
    metadata = event['metadata']
    assert_equal('unallocated_layer', metadata['config'])
    assert_equal('default', metadata['ruleID'])
    assert_equal('', metadata['allocatedExperiment'])
    assert_equal('an_int', metadata['parameterName'])
    assert_equal('false', metadata['isExplicitParameter'])
    assert_equal('Network', metadata['reason'])
  end

  def test_explicit_vs_implicit_parameter_logging
    driver = StatsigDriver.new(SDK_KEY, @options)
    layer = driver.get_layer(@user, 'explicit_vs_implicit_parameter_layer')
    layer.get("an_int", 0)
    layer.get("a_string", 'err')
    driver.shutdown

    assert_equal(2, @events.length)
    event = @events[0]
    assert_equal('statsig::layer_exposure', event['eventName'])
    metadata = event['metadata']
    assert_equal('explicit_vs_implicit_parameter_layer', metadata['config'])
    assert_equal('alwaysPass', metadata['ruleID'])
    assert_equal('experiment', metadata['allocatedExperiment'])
    assert_equal('an_int', metadata['parameterName'])
    assert_equal('true', metadata['isExplicitParameter'])
    assert_equal('Network', metadata['reason'])

    event = @events[1]
    assert_equal('statsig::layer_exposure', event['eventName'])
    metadata = event['metadata']
    assert_equal('explicit_vs_implicit_parameter_layer', metadata['config'])
    assert_equal('alwaysPass', metadata['ruleID'])
    assert_equal('', metadata['allocatedExperiment'])
    assert_equal('a_string', metadata['parameterName'])
    assert_equal('false', metadata['isExplicitParameter'])
    assert_equal('Network', metadata['reason'])
  end

  def test_logs_user_and_event_name
    driver = StatsigDriver.new(SDK_KEY, @options)
    user = StatsigUser.new({ 'userID' => 'dloomb', 'email' => 'dan@loomb.com' })
    layer = driver.get_layer(user, 'unallocated_layer')
    layer.get("an_int", 0)
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::layer_exposure', event['eventName'])
    assert_equal('dloomb', event['user']['userID'])
    assert_equal('dan@loomb.com', event['user']['email'])
  end
end
