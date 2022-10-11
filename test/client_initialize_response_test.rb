require 'http'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

$user_hash = {
  'userID' => '123',
  'email' => 'test@statsig.com',
  'country' => 'US',
  'custom' => {
    'test' => '123',
  },
  'customIDs' => {
    'stableID' => '12345',
  }
}

$statsig_metadata = {
  'sdkType' => 'consistency-test',
  'sessionID' => 'x123'
}

class ClientInitializeResponseTest < Minitest::Test
  def setup
    super
    begin
      @client_key = ENV['test_client_key']
      @secret_key = ENV['test_api_key']
      raise unless !@secret_key.nil? && !@client_key.nil?
    rescue
      raise 'THIS TEST IS EXPECTED TO FAIL FOR NON-STATSIG EMPLOYEES! If this is the only test failing, please proceed to submit a pull request. If you are a Statsig employee, chat with jkw.'
    end
    WebMock.disable!
    WebMock.allow_net_connect!
  end

  def teardown
    super
    Statsig.shutdown
  end

  def test_prod
    server, sdk = get_initialize_responses('https://statsigapi.net/v1')
    validate_consistency(server, sdk)
  end

  def test_prod_with_dev
    server, sdk = get_initialize_responses('https://statsigapi.net/v1', { "tier" => "development" })
    validate_consistency(server, sdk)
  end

  def test_nil_result
    Statsig.initialize("secret-not-valid-key", StatsigOptions.new(local_mode: true))
    result = Statsig.get_client_initialize_response(StatsigUser::new($user_hash))
    assert_nil(result)
  end

  def test_fetch_from_server
    server, sdk = get_initialize_responses('https://statsigapi.net/v1', force_fetch_from_server: true)

    assert_equal(server.keys.sort, sdk.keys.sort)
    server.keys.each do |key|
      if server[key].is_a?(Hash)
        server[key].each do |sub_key, _|
          sdk_value = sdk[key][sub_key]

          case key
          when 'feature_gates'
            assert_equal(false, sdk_value["value"], "Failed comparing #{key} -> #{sub_key}")
          when 'dynamic_configs', 'layer_configs'
            if sdk_value['is_in_layer'] != true
              assert_equal({}, sdk_value["value"], "Failed comparing #{key} -> #{sub_key}")
            end
          else
            # noop
          end
        end
        assert_equal(server[key].keys.sort, sdk[key].keys.sort)
      end
    end
  end

  private

  def get_initialize_responses(api, environment = nil, force_fetch_from_server: false)
    headers = {
      'STATSIG-API-KEY' => @client_key,
      'STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s,
      'Content-Type' => 'application/json; charset=UTF-8'
    }
    http = HTTP.headers(headers).accept(:json)
    server_user_hash = $user_hash.clone
    if environment.nil? == false
      server_user_hash['statsigEnvironment'] = environment
    end
    response = http.post(api + '/initialize', body: JSON.generate({ user: server_user_hash, statsigMetadata: $statsig_metadata }))

    options = StatsigOptions.new(environment, api)
    Statsig.initialize(@secret_key, options)

    if force_fetch_from_server
      mock_fetch_from_server
    end

    [
      JSON.parse(response),
      Statsig.get_client_initialize_response(StatsigUser::new($user_hash))
    ]
  end

  def validate_consistency(server_data, sdk_data)

    server_data.keys.each do |key|
      if server_data[key].is_a? Hash
        assert_equal(server_data[key].keys.sort, sdk_data[key].keys.sort)
      end

      if server_data[key].is_a?(Hash)
        server_data[key].each do |sub_key, _|
          server_value = rm_secondary_exposure_hashes(server_data[key][sub_key])
          sdk_value = rm_secondary_exposure_hashes(sdk_data[key][sub_key])
          if server_value.nil?
            assert_nil(sdk_value, "Failed comparing #{key} -> #{sub_key}")
          else
            assert_equal(server_value, sdk_value, "Failed comparing #{key} -> #{sub_key}")
          end
        end
      elsif !%w[generator time].include?(key)
        assert_equal(sdk_data[key], server_data[key], "Failed comparing #{key}")
      end
    end
  end

  def rm_secondary_exposure_hashes(value)
    if !value.is_a?(Hash) || value["secondary_exposures"].nil?
      return
    end

    value["secondary_exposures"].each do |entry|
      entry["gate"] = "__REMOVED_FOR_TEST__"
    end
    value
  end

  def mock_fetch_from_server
    shared_instance = Statsig.instance_variable_get("@shared_instance")
    evaluator = shared_instance.instance_variable_get("@evaluator")
    evaluator.instance_eval do
      def eval_spec(_, _)
        "fetch_from_server"
      end
    end
  end
end