

require_relative 'test_helper'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'dynamic_config'
require 'layer'

class TestSymbolHashes < BaseTest
  suite :TestSymbolHashes

  def before_setup
    super

    json_file = File.read("#{__dir__}/data/download_config_specs_symbol_hashes_test.json")
    @mock_response = JSON.parse(json_file).to_json
    @options = StatsigOptions.new(disable_diagnostics_logging: true)

    WebMock.enable!
    stub_download_config_specs.to_return(status: 200, body: @mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
  end

  def setup
    super
    Statsig.initialize(SDK_KEY)
  end

  def teardown
    Statsig.shutdown
    WebMock.reset!
    WebMock.disable!
  end

  def test_fails_when_just_user_id
    result = Statsig.check_gate(StatsigUser.new({ :userID => "this_user_fails" }), "a_gate")
    assert_equal(false, result)
  end

  def test_passes_from_private_attributes
    user = StatsigUser.new({ :userID => "this_user_fails", :private_attributes => { :email => "a@statsig.com" } })
    result = Statsig.check_gate(user, "a_gate")
    assert_equal(true, result)
  end

  def test_passes_from_custom_field
    result = Statsig.check_gate(StatsigUser.new({ :userID => "this_user_fails", :custom => { :plays_league => "yes" } }), "a_gate")
    assert_equal(true, result)
  end

  def test_passes_from_environment
    result = Statsig.check_gate(StatsigUser.new({ :userID => "this_user_fails", :statsigEnvironment => { :tier => "hax" } }), "a_gate")
    assert_equal(true, result)
  end

  def test_passes_from_stable_id
    result = Statsig.check_gate(StatsigUser.new({ :userID => "a_user", :custom_ids => { :stableID => "good_stable_id" } }), "a_gate")
    assert_equal(true, result)
  end
end