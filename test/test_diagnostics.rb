# typed: true

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'statsig'
require_relative './dummy_data_adapter'

$expected_sync_time = 1631638014811

class InitDiagnosticsTest < BaseTest
  suite :InitDiagnosticsTest
  def setup
    super
    WebMock.enable!
    json_file = File.read("#{__dir__}/data/download_config_specs.json")
    @mock_response = JSON.parse(json_file).to_json

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(
      status: 200,
      headers: { 'x-statsig-region' => 'az-westus-2' }
    )
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(
      status: 200,
      body: @mock_response,
      headers: { 'x-statsig-region' => 'az-westus-2' }
    )

    @events = []
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200, body: lambda { |request|
      @events.push(*JSON.parse(request.body)['events'])
      return ''
    })
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_id_lists
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200, body:
      JSON.generate({ "my_id_list": {
        "name": :"my_id_list", "size": 1, "url": 'https://fakecdn.com/my_id_list', "creationTime": 1, "fileID": 'a_file_id'
      } }), headers: { 'x-statsig-region' => 'az-westus-2' })
    stub_request(:get, 'https://fakecdn.com/my_id_list').to_return(status: 200, body: '+asdfcd',
                                                                   headers: { "content-length": 1 })

    driver = StatsigDriver.new('secret-key')
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('initialize', metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], 'overall', 'start')
    # skip 4 markers for download_config_specs
    assert_marker_equal(markers[5], 'get_id_list_sources', 'start', 'network_request')
    assert_marker_equal(markers[6], 'get_id_list_sources', 'end', 'network_request',
                        { 'statusCode' => 200, 'sdkRegion' => 'az-westus-2' })
    assert_marker_equal(markers[7], 'get_id_list_sources', 'start', 'process', { 'idListCount' => 1 })
    assert_marker_equal(markers[8], 'get_id_list', 'start', 'network_request',
                        { 'url' => 'https://fakecdn.com/my_id_list' })
    assert_marker_equal(markers[9], 'get_id_list', 'end', 'network_request',
                        { 'statusCode' => 200, 'url' => 'https://fakecdn.com/my_id_list' })
    assert_marker_equal(markers[10], 'get_id_list', 'start', 'process', { 'url' => 'https://fakecdn.com/my_id_list' })
    assert_marker_equal(markers[11], 'get_id_list', 'end', 'process',
                        { 'success' => true, 'url' => 'https://fakecdn.com/my_id_list' })
    assert_marker_equal(markers[12], 'get_id_list_sources', 'end', 'process', { 'idListCount' => 1, 'success' => true })
    assert_marker_equal(markers[13], 'overall', 'end', nil, { 'success' => true })
    assert_equal(14, markers.length)
  end

  def test_network_init_success
    driver = StatsigDriver.new('secret-key')
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('initialize', metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], 'overall', 'start')
    assert_marker_equal(markers[1], 'download_config_specs', 'start', 'network_request')
    assert_marker_equal(markers[2], 'download_config_specs', 'end', 'network_request',
                        { 'statusCode' => 200, 'sdkRegion' => 'az-westus-2' })
    assert_marker_equal(markers[3], 'download_config_specs', 'start', 'process')
    assert_marker_equal(markers[4], 'download_config_specs', 'end', 'process', { 'success' => true })
    assert_marker_equal(markers[5], 'get_id_list_sources', 'start', 'network_request')
    assert_marker_equal(markers[6], 'get_id_list_sources', 'end', 'network_request',
                        { 'statusCode' => 200, 'sdkRegion' => 'az-westus-2' })
    assert_marker_equal(markers[7], 'overall', 'end', nil, { 'success' => true})
    assert_equal(8, markers.length)
  end

  def test_network_init_failure
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(
      status: 500,
      headers: { 'x-statsig-region' => 'az-westus-2' }
    )

    driver = StatsigDriver.new('secret-key')
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('initialize', metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], 'overall', 'start')
    assert_marker_equal(markers[1], 'download_config_specs', 'start', 'network_request')
    assert_marker_equal(markers[2], 'download_config_specs', 'end', 'network_request',
                        { 'statusCode' => 500, 'sdkRegion' => 'az-westus-2' })
    assert_marker_equal(markers[3], 'get_id_list_sources', 'start', 'network_request')
    assert_marker_equal(markers[4], 'get_id_list_sources', 'end', 'network_request',
                        { 'statusCode' => 200, 'sdkRegion' => 'az-westus-2' })
    assert_marker_equal(markers[5], 'overall', 'end', nil, { 'success' => true })
    assert_equal(6, markers.length)
  end

  def test_bootstrap_init
    driver = StatsigDriver.new('secret-key', StatsigOptions.new(bootstrap_values: @mock_response))
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('initialize', metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], 'overall', 'start')
    assert_marker_equal(markers[1], 'bootstrap', 'start', 'process')
    assert_marker_equal(markers[2], 'bootstrap', 'end', 'process', { 'success' => true })
    assert_marker_equal(markers[3], 'get_id_list_sources', 'start', 'network_request')
    assert_marker_equal(markers[4], 'get_id_list_sources', 'end', 'network_request',
                        { 'statusCode' => 200, 'sdkRegion' => 'az-westus-2' })
    assert_marker_equal(markers[5], 'overall', 'end', nil, { 'success' => true })
    assert_equal(6, markers.length)
  end

  def test_data_adapter_init
    driver = StatsigDriver.new('secret-key', StatsigOptions.new(data_store: DummyDataAdapter.new))
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('initialize', metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], 'overall', 'start')
    assert_marker_equal(markers[1], 'data_store_config_specs', 'start', 'fetch')
    assert_marker_equal(markers[2], 'data_store_config_specs', 'end', 'fetch', { 'success' => true })
    assert_marker_equal(markers[3], 'data_store_config_specs', 'start', 'process')
    assert_marker_equal(markers[4], 'data_store_config_specs', 'end', 'process', { 'success' => true })
    assert_marker_equal(markers[5], 'data_store_id_lists', 'start', 'fetch')
    assert_marker_equal(markers[6], 'data_store_id_lists', 'end', 'fetch', { 'success' => true })
    assert_marker_equal(markers[7], 'data_store_id_lists', 'start', 'process', { 'idListCount' => 1 })
    assert_marker_equal(markers[8], 'data_store_id_list', 'start', 'fetch', { 'url' => 'https://idliststorage.fake' })
    assert_marker_equal(markers[9], 'data_store_id_list', 'end', 'fetch',
                        { 'success' => true, 'url' => 'https://idliststorage.fake' })
    assert_marker_equal(markers[10], 'data_store_id_list', 'start', 'process',
                        { 'url' => 'https://idliststorage.fake' })
    assert_marker_equal(markers[11], 'data_store_id_list', 'end', 'process',
                        { 'success' => true, 'url' => 'https://idliststorage.fake' })
    assert_marker_equal(markers[12], 'data_store_id_lists', 'end', 'process', { 'idListCount' => 1, 'success' => true })
    assert_marker_equal(markers[13], 'overall', 'end', nil, { 'success' => true })
    assert_equal(14, markers.length)
  end

  def test_api_call_diagnostics
    Statsig.initialize('secret-key')
    Spy.on(Statsig::Diagnostics, 'sample').and_return do
      true
    end
    user = StatsigUser.new(user_id: 'test-user')
    Statsig.check_gate_with_exposure_logging_disabled(user, 'non-existent-gate')
    Statsig.get_config_with_exposure_logging_disabled(user, 'non-existent-config')
    Statsig.get_experiment_with_exposure_logging_disabled(user, 'non-existent-experiment')
    Statsig.get_layer_with_exposure_logging_disabled(user, 'non-existent-layer')
    Statsig.shutdown
    Spy.off(Statsig::Diagnostics, 'sample')

    keys = Statsig::Diagnostics::API_CALL_KEYS

    events = @events[1..-1] # skip initialize diagnostics
    assert_equal(4, events.length)
    events.each_with_index do |event, index|
      assert_equal('statsig::diagnostics', event['eventName'])
      metadata = event['metadata']
      assert_equal('api_call', metadata['context'])
      markers = metadata['markers']
      assert_marker_equal(markers[0], keys[index], 'start')
      assert_marker_equal(markers[1], keys[index], 'end', nil, { 'success' => true })
    end
  end

  def test_disable_diagnostics_logging
    Statsig.initialize('secret-key', StatsigOptions.new(disable_diagnostics_logging: true))
    user = StatsigUser.new(user_id: 'test-user')
    Statsig.check_gate_with_exposure_logging_disabled(user, 'non-existent-gate')
    Statsig.get_config_with_exposure_logging_disabled(user, 'non-existent-config')
    Statsig.get_experiment_with_exposure_logging_disabled(user, 'non-existent-experiment')
    Statsig.get_layer_with_exposure_logging_disabled(user, 'non-existent-layer')
    Statsig.shutdown

    assert_equal(0, @events.length)
  end

  def test_diagnostics_sampling
    json_file = File.read("#{__dir__}/data/download_config_specs.json")
    @mock_response = JSON.parse(json_file)
    @mock_response['diagnostics'] = {
      "download_config_specs": 5000,
      "get_id_list": 5000,
      "get_id_list_sources": 5000
    }
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(
      status: 200,
      body: @mock_response.to_json,
      headers: { 'x-statsig-region' => 'az-westus-2' }
    )
    driver = StatsigDriver.new(
      'secret-key',
      StatsigOptions.new(
        disable_rulesets_sync: true,
        disable_idlists_sync: true,
        logging_interval_seconds: 9999
      )
    )
    logger = driver.instance_variable_get('@logger')
    logger.flush

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('initialize', metadata['context'])
    @events = []

    10.times do
      driver.manually_sync_rulesets
    end
    logger.flush

    assert(
      @events.length < 10 && @events.length.positive?,
      "Expected between 0 and 10 events, received #{@events.length}"
    )
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('config_sync', metadata['context'])
    @events = []

    10.times do
      driver.manually_sync_idlists
    end
    logger.flush

    assert(
      @events.length < 10 && @events.length.positive?,
      "Expected between 0 and 10 events, received #{@events.length}"
    )
    event = @events[0]
    assert_equal('statsig::diagnostics', event['eventName'])

    metadata = event['metadata']
    assert_equal('config_sync', metadata['context'])

    driver.shutdown
  end

  private

  def assert_marker_equal(marker, key, action, step = nil, tags = {})
    assert_equal(key, marker['key'])
    assert_equal(action, marker['action'])
    assert(step == marker['step'], "expected #{step} but received #{marker['step']}")
    tags.each do |key, val|
      assert_equal(val, marker[key], "expected #{val} but received #{marker[key]}")
    end
    assert_instance_of(Integer, marker['timestamp'])
  end
end