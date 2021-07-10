require 'http'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'

class ServerSDKConsistencyTest < Minitest::Test
  def setup
    super
    begin
      secret = ENV['test_api_key'] || File.read("#{__dir__}/../../ops/secrets/prod_keys/statsig-rulesets-eval-consistency-test-secret.key")
    rescue
      raise 'THIS TEST IS EXPECTED TO FAIL FOR NON-STATSIG EMPLOYEES! If this is the only test failing, please proceed to submit a pull request. If you are a Statsig employee, chat with jkw.'
    end

    http = HTTP.headers(
      {"STATSIG-API-KEY" => secret,
       "STATSIG-CLIENT-TIME" => (Time.now.to_f * 1000).to_s,
       "Content-Type" => "application/json; charset=UTF-8"
      }).accept(:json)
    response = http.post('https://api.statsig.com/v1/rulesets_e2e_test', body: JSON.generate({}))
    @prodData = JSON.parse(response)['data']
    
    response = http.post('https://latest.api.statsig.com/v1/rulesets_e2e_test', body: JSON.generate({}))
    @stagingData = JSON.parse(response)['data']

    Statsig.initialize(secret)
  end

  def test_prod_consistency
    validate_consistency(@prodData)
  end

  def test_staging_consistency
    validate_consistency(@stagingData)
  end

  def validate_consistency(data)
    i = 0

    until i >= data.length do
      user = StatsigUser.new(data[i]['user'])
      gates = data[i]['feature_gates']
      configs = data[i]['dynamic_configs']

      gates.each do |name, value|
        assert(Statsig.check_gate(user, name) == value)
      end

      configs.each do |name, value|
        config_value = value['value']
        rule_id = value['rule_id']
        sdkConfig = Statsig.get_config(user, name)

        assert(sdkConfig.value == config_value)
        assert(sdkConfig.rule_id == rule_id)
      end

      i += 1
    end
  end
end