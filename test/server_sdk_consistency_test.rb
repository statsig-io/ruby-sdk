require 'http'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'pp'
require 'statsig'

class ServerSDKConsistencyTest < Minitest::Test
  def setup
    super
    begin
      @secret = ENV['test_api_key'] || File.read("#{__dir__}/../../ops/secrets/prod_keys/statsig-rulesets-eval-consistency-test-secret.key")
    rescue
      raise 'THIS TEST IS EXPECTED TO FAIL FOR NON-STATSIG EMPLOYEES! If this is the only test failing, please proceed to submit a pull request. If you are a Statsig employee, chat with jkw.'
    end
  end

  def test_prod
    validate_consistency('https://api.statsig.com/v1')
  end

  def test_staging
    validate_consistency('https://latest.api.statsig.com/v1')
  end

  def test_uswest
    validate_consistency('https://us-west-2.api.statsig.com/v1')
  end

  def test_useast
    validate_consistency('https://us-east-2.api.statsig.com/v1')
  end

  def test_apsouth
    validate_consistency('https://ap-south-1.api.statsig.com/v1')
  end

  def validate_consistency(apiOverride)
    puts "Testing for #{apiOverride}"

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
      gates = data[i]['feature_gates']
      configs = data[i]['dynamic_configs']

      gates.each do |name, value|
        sdk_result = driver.check_gate(user, name)
        pp "Failed validation for gate #{name}", user, "Expected: #{value}", "Actual: #{sdk_result}" unless sdk_result == value
        assert(sdk_result == value)
      end

      configs.each do |name, value|
        config_value = value['value']
        rule_id = value['rule_id']
        sdkConfig = driver.get_config(user, name)

        assert(sdkConfig.value == config_value)
        assert(sdkConfig.rule_id == rule_id)
      end

      i += 1
    end
  end
end