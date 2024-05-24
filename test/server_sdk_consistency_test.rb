# typed: false
require_relative 'test_helper'
require 'http'
require 'json'
require 'pp'

class ServerSDKConsistencyTest < BaseTest
  suite :ServerSDKConsistencyTest

  def setup
    super
    begin
      @secret = ENV['test_api_key']
    rescue StandardError
      raise 'THIS TEST IS EXPECTED TO FAIL FOR NON-STATSIG EMPLOYEES! If this is the only test failing, please proceed to submit a pull request. If you are a Statsig employee, chat with jkw.'
    end
    WebMock.reset!
    WebMock.disable!
    WebMock.allow_net_connect!
  end

  def teardown
    super
    WebMock.disable_net_connect!
  end

  def test_prod
    validate_consistency('https://statsigapi.net/v1')
  end

  def test_staging
    validate_consistency('https://staging.statsigapi.net/v1')
  end

  def validate_consistency(api_override)
    puts "\nTesting for #{api_override}"

    http = HTTP.headers(
      { 'STATSIG-API-KEY' => @secret,
        'STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s,
        'Content-Type' => 'application/json; charset=UTF-8' }
    ).accept(:json)
    response = http.post("#{api_override}/rulesets_e2e_test", body: JSON.generate({}))
    data = JSON.parse(response, { symbolize_names: true })[:data]

    options = StatsigOptions.new(nil, api_override)
    driver = StatsigDriver.new(@secret, options)

    i = 0
    until i >= data.length
      user = StatsigUser.new(data[i][:user])
      gates = data[i][:feature_gates_v2]
      configs = data[i][:dynamic_configs]
      layers = data[i][:layer_configs]

      sdk_results = driver.get_client_initialize_response(user, 'none', nil, false)

      gates.each do |name, server_result|
        sdk_result = sdk_results[:feature_gates][name.to_s]
        validate_config(user, sdk_result, server_result)
      end

      configs.each do |name, server_result|
        sdk_result = sdk_results[:dynamic_configs][name.to_s]
        validate_config(user, sdk_result, server_result)
      end

      layers.each do |name, server_result|
        sdk_result = sdk_results[:layer_configs][name.to_s]
        validate_config(user, sdk_result, server_result)
      end

      i += 1
    end
  end

  def validate_config(user, sdk_result, server_result)
    user_display = user.serialize(false)

    if server_result[:value].nil?
      assert_nil(sdk_result[:value])
    else
      assert_equal(JSON.generate(server_result[:value]), JSON.generate(sdk_result[:value]),
                   "Different values for #{server_result[:name]}\n #{user_display}")
    end

    if server_result[:rule_id].nil?
      assert_nil(sdk_result[:rule_id])
    else
      assert_equal(server_result[:rule_id], sdk_result[:rule_id],
                   "Different rule IDs for #{server_result[:name]}\n #{user_display}")
    end

    if server_result[:secondary_exposures].nil?
      assert_nil(sdk_result[:secondary_exposures])
    else
      assert_equal(server_result[:secondary_exposures], sdk_result[:secondary_exposures],
                   "Different secondary exposures for #{server_result[:name]}\n #{user_display}")
    end

    if server_result[:undelegated_secondary_exposures].nil?
      assert_nil(sdk_result[:undelegated_secondary_exposures])
    else
      assert_equal(server_result[:undelegated_secondary_exposures], sdk_result[:undelegated_secondary_exposures],
                   "Different undelegated secondary exposures for #{server_result[:name]}\n #{user_display}")
    end
  end
end
