require 'http'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'pp'
require 'statsig'
require 'webmock/minitest'

class ServerSDKConsistencyTest < Minitest::Test
  def setup
    super
    begin
      @secret = ENV['test_api_key'] || File.read("#{__dir__}/../../ops/secrets/prod_keys/statsig-rulesets-eval-consistency-test-secret.key")
    rescue
      raise 'THIS TEST IS EXPECTED TO FAIL FOR NON-STATSIG EMPLOYEES! If this is the only test failing, please proceed to submit a pull request. If you are a Statsig employee, chat with jkw.'
    end
    WebMock.disable!
    WebMock.allow_net_connect!
  end

  def test_prod
    validate_consistency('https://api.statsig.com/v1')
  end

  def test_staging
    validate_consistency('https://latest.api.statsig.com/v1')
  end

  def validate_consistency(apiOverride)
    puts "\nTesting for #{apiOverride}"

    http = HTTP.headers(
      {"STATSIG-API-KEY" => @secret,
       "STATSIG-CLIENT-TIME" => (Time.now.to_f * 1000).to_s,
       "Content-Type" => "application/json; charset=UTF-8"
      }).accept(:json)
    response = http.post(apiOverride + '/rulesets_e2e_test', body: JSON.generate({}))
    data = JSON.parse(response)['data']

    options = StatsigOptions.new(nil, apiOverride)
    driver = StatsigDriver.new(@secret, options)

    i = 0
    until i >= data.length do
      user = StatsigUser.new(data[i]['user'])
      gates = data[i]['feature_gates_v2']
      configs = data[i]['dynamic_configs']
      layers = data[i]['layer_configs']

      gates.each do |name, server_result|
        sdk_result = driver.instance_variable_get('@evaluator').check_gate(user, name)
        if sdk_result.gate_value != server_result['value']
          pp "Different values for gate #{name}", user, "Expected: #{server_result['value']}", "Actual: #{sdk_result.gate_value}"
        end
        assert(sdk_result.gate_value == server_result['value'])

        if sdk_result.rule_id != server_result['rule_id']
          pp "Different rule IDs for gate #{name}", user, "Expected: #{server_result['rule_id']}", "Actual: #{sdk_result.rule_id}"
        end
        assert(sdk_result.rule_id == server_result['rule_id'])

        if sdk_result.secondary_exposures != server_result['secondary_exposures']
          pp "Different secondary exposures for gate #{name}", user,
             "Expected: #{server_result['secondary_exposures']}", "Actual: #{sdk_result.secondary_exposures}"
        end
        assert(sdk_result.secondary_exposures == server_result['secondary_exposures'])
      end

      configs.each do |name, server_result|
        sdk_result = driver.instance_variable_get('@evaluator').get_config(user, name)
        validate_config(user, sdk_result, server_result)
      end

      layers.each do |name, server_result|
        sdk_result = driver.instance_variable_get('@evaluator').get_layer(user, name)
        validate_config(user, sdk_result, server_result)

        if sdk_result.undelegated_sec_exps != server_result['undelegated_secondary_exposures']
          pp "Different undelegated secondary exposures for config #{name}", user,
             "Expected: #{server_result['undelegated_secondary_exposures']}", "Actual: #{sdk_result.undelegated_sec_exps}"
        end
        assert(sdk_result.undelegated_sec_exps == server_result['undelegated_secondary_exposures'])
      end

      i += 1
    end
  end

  def validate_config(user, sdk_result, server_result)
    config_value = server_result['value']
    rule_id = server_result['rule_id']

    if sdk_result.json_value != server_result['value']
      pp "Different values for config #{name}", user, "Expected: #{server_result['value']}", "Actual: #{sdk_result.json_value}"
    end
    assert(sdk_result.json_value == config_value)

    if sdk_result.rule_id != server_result['rule_id']
      pp "Different rule IDs for config #{name}", user, "Expected: #{server_result['rule_id']}", "Actual: #{sdk_result.rule_id}"
    end
    assert(sdk_result.rule_id == rule_id)

    if sdk_result.secondary_exposures != server_result['secondary_exposures']
      pp "Different secondary exposures for config #{name}", user,
         "Expected: #{server_result['secondary_exposures']}", "Actual: #{sdk_result.secondary_exposures}"
    end
    assert(sdk_result.secondary_exposures == server_result['secondary_exposures'])
  end
end