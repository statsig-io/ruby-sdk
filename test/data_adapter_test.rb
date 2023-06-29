# typed: false

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'statsig_user'
require_relative './dummy_data_adapter'

class StatsigDataAdapterTest < Minitest::Test
  def setup
    super
    WebMock.enable!
    @mock_dcs = JSON.parse(File.read("#{__dir__}/data/download_config_specs.json")).to_json
    @mock_get_id_lists = JSON.parse(File.read("#{__dir__}/data/get_id_lists.json")).to_json

    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @mock_dcs)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200, body: @mock_get_id_lists)
    @user = StatsigUser.new({ 'userID' => 'a_user' })
    @user_in_idlist_1 = StatsigUser.new({ 'userID' => 'a-user' })
    @user_in_idlist_2 = StatsigUser.new({ 'userID' => 'b-user' })
    @user_not_in_idlist = StatsigUser.new({ 'userID' => 'c-user' })
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_datastore
    options = StatsigOptions.new
    options.local_mode = true
    options.data_store = DummyDataAdapter.new
    driver = StatsigDriver.new('secret-testcase', options)
    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
  end

  def test_datastore_overwritten_by_network
    options = StatsigOptions.new(rulesets_sync_interval: 1, idlists_sync_interval: 1)
    options.data_store = DummyDataAdapter.new
    driver = StatsigDriver.new('secret-testcase', options)

    evaluator = driver.instance_variable_get('@evaluator')
    store = evaluator.instance_variable_get('@spec_store')
    spy_sync_rulesets = Spy.on(store, :download_config_specs).and_call_through
    spy_sync_id_lists = Spy.on(store, :get_id_lists_from_network).and_call_through
    wait_for(timeout: 1.9) do
      spy_sync_rulesets.calls.size.positive?
      spy_sync_id_lists.calls.size.positive?
    end

    adapter_specs = options.data_store&.get(Statsig::Interfaces::IDataStore::CONFIG_SPECS_KEY)
    specs_json = JSON.parse(adapter_specs)
    assert(specs_json == JSON.parse(@mock_dcs))
    assert(specs_json["feature_gates"].size === 4)
    assert(specs_json["feature_gates"][0]["name"] === "email_not_null")

    adapter_idlists = options.data_store&.get(Statsig::Interfaces::IDataStore::ID_LISTS_KEY)
    idlists_json = JSON.parse(adapter_idlists)
    assert(idlists_json == JSON.parse(@mock_get_id_lists))
    assert(idlists_json.size === 1)
    assert(idlists_json["idlist1"]["size"] === 12)
    assert(idlists_json["idlist1"]["fileID"] === "123")

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)

    result = driver.get_config(@user, "test_config")
    assert(result.get("number", 3) == 4)

    result = driver.check_gate(@user, "always_on_gate")
    assert(result == true)
  end

  def test_datastore_and_bootstrap_ignores_bootstrap
    options = StatsigOptions.new
    options.data_store = DummyDataAdapter.new
    options.bootstrap_values = @mock_response
    options.local_mode = true
    driver = StatsigDriver.new('secret-testcase', options)
    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)

    result = driver.check_gate(@user, "always_on_gate")
    assert(result == false)
  end

  def test_datastore_used_for_polling
    options = StatsigOptions.new(rulesets_sync_interval: 1, idlists_sync_interval: 1, local_mode: true)
    options.data_store = DummyDataAdapter.new(poll_config_specs: true, poll_id_lists: true)
    driver = StatsigDriver.new('secret-testcase', options)

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == true)
    result = driver.check_gate(@user_in_idlist_2, "test_id_list")
    assert(result == true)
    result = driver.check_gate(@user_not_in_idlist, "test_id_list")
    assert(result == false)

    options.data_store.remove_feature_gate("gate_from_adapter")
    options.data_store.update_id_lists

    evaluator = driver.instance_variable_get('@evaluator')
    store = evaluator.instance_variable_get('@spec_store')
    spy_sync_rulesets = Spy.on(store, :load_config_specs_from_storage_adapter).and_call_through
    spy_sync_id_lists = Spy.on(store, :get_id_lists_from_adapter).and_call_through
    wait_for(timeout: 1.9) do
      spy_sync_rulesets.calls.size.positive?
      spy_sync_id_lists.calls.size.positive?
    end

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == false)
    result = driver.check_gate(@user_in_idlist_2, "test_id_list")
    assert(result == false)
    result = driver.check_gate(@user_not_in_idlist, "test_id_list")
    assert(result == true)
  end

  def test_datastore_fallback_to_network
    options = StatsigOptions.new(rulesets_sync_interval: 1, idlists_sync_interval: 1)
    options.data_store = DummyDataAdapter.new(poll_config_specs: true, poll_id_lists: true)
    driver = StatsigDriver.new('secret-testcase', options)

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == true)

    options.data_store.corrupt_store

    evaluator = driver.instance_variable_get('@evaluator')
    store = evaluator.instance_variable_get('@spec_store')
    spy_sync_rulesets = Spy.on(store, :download_config_specs).and_call_through
    spy_sync_id_lists = Spy.on(store, :get_id_lists_from_network).and_call_through
    wait_for(timeout: 1.9) do
      spy_sync_rulesets.calls.size.positive?
      spy_sync_id_lists.calls.size.positive?
    end

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == false)
    result = driver.check_gate(@user, "always_on_gate")
    assert(result == true)
  end
end
