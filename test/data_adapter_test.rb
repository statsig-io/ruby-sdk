require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'statsig_user'
require_relative './dummy_data_adapter'

class StatsigDataAdapterTest < Minitest::Test
  @@json_file = File.read("#{__dir__}/download_config_specs.json")
  @@mock_response = JSON.parse(@@json_file).to_json

  def setup
    super
    WebMock.enable!
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @@mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @user = StatsigUser.new({'userID' => 'a_user'})
  end

  def teardown
    super
    WebMock.disable!
  end

  def test_datastore
    options = StatsigOptions.new()
    options.local_mode = true
    options.data_store = DummyDataAdapter.new()
    driver = StatsigDriver.new('secret-testcase', options)
    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
  end

  def test_datastore_overwritten_by_network
    options = StatsigOptions.new()
    options.data_store = DummyDataAdapter.new()
    driver = StatsigDriver.new('secret-testcase', options)

    adapter = options.data_store.get("statsig.cache")
    adapter_json = JSON.parse(adapter)
    assert(adapter_json == JSON.parse(@@mock_response))
    assert(adapter_json["feature_gates"].size === 4)
    assert(adapter_json["feature_gates"][0]["name"] === "email_not_null")

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)

    result = driver.get_config(@user, "test_config")
    assert(result.get("number", 3) == 4)

    result = driver.check_gate(@user, "always_on_gate")
    assert(result == true)
  end

  def test_datastore_and_bootstrap_ignores_bootstrap
    options = StatsigOptions.new()
    options.data_store = DummyDataAdapter.new()
    options.bootstrap_values = @@mock_response
    options.local_mode = true
    driver = StatsigDriver.new('secret-testcase', options)
    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)

    result = driver.check_gate(@user, "always_on_gate")
    assert(result == false)
  end
end