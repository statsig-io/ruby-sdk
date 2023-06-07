# typed: true

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'statsig'
require_relative './dummy_data_adapter'

$expected_sync_time = 1631638014811

class InitDiagnosticsTest < Minitest::Test
  def setup
    super
    WebMock.enable!
    json_file = File.read("#{__dir__}/data/download_config_specs.json")
    @mock_response = JSON.parse(json_file).to_json

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @mock_response)

    @events = []
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200, body: lambda { |request|
      @events.push(*JSON.parse(request.body)["events"])
      return ''
    })
  end

  def teardown
    super
    WebMock.disable!
  end

  def test_id_lists
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200, body:
      JSON.generate({ "my_id_list": {
        "name": :"my_id_list", "size": 1, "url": "https://fakecdn.com/my_id_list", "creationTime": 1, "fileID": "a_file_id"
      } }))
    stub_request(:get, 'https://fakecdn.com/my_id_list').to_return(status: 200, body: "+asdfcd", headers: { "content-length": 1 })

    driver = StatsigDriver.new('secret-key')
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal("statsig::diagnostics", event['eventName'])

    metadata = event['metadata']
    assert_equal("initialize", metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], "overall", "start")
    # skip 4 markers for download_config_specs
    assert_marker_equal(markers[5], "get_id_list_sources", "start", "network_request")
    assert_marker_equal(markers[6], "get_id_list_sources", "end", "network_request", 200)
    assert_marker_equal(markers[7], "get_id_list_sources", "start", "process", 1)
    assert_marker_equal(markers[8], "get_id_list", "start", "network_request", nil, {"url"=>"https://fakecdn.com/my_id_list"})
    assert_marker_equal(markers[9], "get_id_list", "end", "network_request", 200, {"url"=>"https://fakecdn.com/my_id_list"})
    assert_marker_equal(markers[10], "get_id_list", "start", "process", nil, {"url"=>"https://fakecdn.com/my_id_list"})
    assert_marker_equal(markers[11], "get_id_list", "end", "process", true, {"url"=>"https://fakecdn.com/my_id_list"})
    assert_marker_equal(markers[12], "get_id_list_sources", "end", "process", true)
    assert_marker_equal(markers[13], "overall", "end", nil, "success")
    assert_equal(14, markers.length)
  end

  def test_network_init_success
    driver = StatsigDriver.new('secret-key')
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal("statsig::diagnostics", event['eventName'])

    metadata = event['metadata']
    assert_equal("initialize", metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], "overall", "start")
    assert_marker_equal(markers[1], "download_config_specs", "start", "network_request")
    assert_marker_equal(markers[2], "download_config_specs", "end", "network_request", 200)
    assert_marker_equal(markers[3], "download_config_specs", "start", "process")
    assert_marker_equal(markers[4], "download_config_specs", "end", 'process', true)
    assert_marker_equal(markers[5], "get_id_list_sources", "start", "network_request")
    assert_marker_equal(markers[6], "get_id_list_sources", "end", "network_request", 200)
    assert_marker_equal(markers[7], "overall", "end", nil, "success")
    assert_equal(8, markers.length)
  end

  def test_network_init_failure
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 500)

    driver = StatsigDriver.new('secret-key')
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal("statsig::diagnostics", event['eventName'])

    metadata = event['metadata']
    assert_equal("initialize", metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], "overall", "start")
    assert_marker_equal(markers[1], "download_config_specs", "start", "network_request")
    assert_marker_equal(markers[2], "download_config_specs", "end", "network_request", 500)
    assert_marker_equal(markers[3], "get_id_list_sources", "start", "network_request")
    assert_marker_equal(markers[4], "get_id_list_sources", "end", "network_request", 200)
    assert_marker_equal(markers[5], "overall", "end", nil, "success")
    assert_equal(6, markers.length)
  end

  def test_bootstrap_init
    driver = StatsigDriver.new('secret-key', StatsigOptions.new(bootstrap_values: @mock_response))
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal("statsig::diagnostics", event['eventName'])

    metadata = event['metadata']
    assert_equal("initialize", metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], "overall", "start")
    assert_marker_equal(markers[1], "bootstrap", "start", "process")
    assert_marker_equal(markers[2], "bootstrap", "end", "process", true)
    assert_marker_equal(markers[3], "get_id_list_sources", "start", "network_request")
    assert_marker_equal(markers[4], "get_id_list_sources", "end", "network_request", 200)
    assert_marker_equal(markers[5], "overall", "end", nil, "success")
    assert_equal(6, markers.length)
  end

  def test_data_adapter_init
    driver = StatsigDriver.new('secret-key', StatsigOptions.new(data_store: DummyDataAdapter.new))
    driver.shutdown

    assert_equal(1, @events.length)
    event = @events[0]
    assert_equal("statsig::diagnostics", event['eventName'])

    metadata = event['metadata']
    assert_equal("initialize", metadata['context'])

    markers = metadata['markers']
    assert_marker_equal(markers[0], "overall", "start")
    assert_marker_equal(markers[1], "data_store_config_specs", "start", "fetch")
    assert_marker_equal(markers[2], "data_store_config_specs", "end", "fetch", true)
    assert_marker_equal(markers[3], "data_store_config_specs", "start", "process")
    assert_marker_equal(markers[4], "data_store_config_specs", "end", "process", true)
    assert_marker_equal(markers[5], "data_store_id_lists", "start", "fetch")
    assert_marker_equal(markers[6], "data_store_id_lists", "end", "fetch", true)
    assert_marker_equal(markers[7], "data_store_id_lists", "start", "process", 1)
    assert_marker_equal(markers[8], "data_store_id_list", "start", "fetch", nil, {"url"=>"https://idliststorage.fake"})
    assert_marker_equal(markers[9], "data_store_id_list", "end", "fetch", true, {"url"=>"https://idliststorage.fake"})
    assert_marker_equal(markers[10], "data_store_id_list", "start", "process", nil, {"url"=>"https://idliststorage.fake"})
    assert_marker_equal(markers[11], "data_store_id_list", "end", "process", true, {"url"=>"https://idliststorage.fake"})
    assert_marker_equal(markers[12], "data_store_id_lists", "end", "process", true)
    assert_marker_equal(markers[13], "overall", "end", nil, "success")
    assert_equal(14, markers.length)
  end

  private

  def assert_marker_equal(marker, key, action, step = nil, value = nil, metadata = nil)
    assert_equal(key, marker['key'])
    assert_equal(action, marker['action'])
    assert(step == marker['step'], "expected #{step} but received #{marker['step']}")
    assert(value == marker['value'], "expected #{value} but received #{marker['value']}")
    assert(metadata == marker['metadata'], "expected #{metadata} but received #{marker['metdata']}")
    assert_instance_of(Integer, marker['timestamp'])
  end
end