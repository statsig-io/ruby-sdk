# typed: false

require_relative 'test_helper'
require 'http'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

USER_HASH = {
  'userID' => '123',
  'email' => 'test@statsig.com',
  'country' => 'US',
  'custom' => {
    'test' => '123',
    'sdk' => 'ruby'
  },
  'customIDs' => {
    'stableID' => '12345'
  }
}.freeze

STATSIG_METADATA = {
  'sdkType' => 'consistency-test',
  'sessionID' => 'x123'
}.freeze

class ClientInitializeResponseTest < BaseTest
  suite :ClientInitializeResponseTest

  def setup
    super
    begin
      @client_key = ENV['test_client_key']
      @secret_key = ENV['test_api_key']
      raise unless !@secret_key.nil? && !@client_key.nil?
    rescue StandardError
      raise "THIS TEST IS EXPECTED TO FAIL FOR NON-STATSIG EMPLOYEES! If this is the only test failing, please \n" \
            'proceed to submit a pull request. If you are a Statsig employee, chat with jkw.'
    end
    WebMock.reset!
    WebMock.disable!
    WebMock.allow_net_connect!
  end

  def teardown
    super
    Statsig.shutdown
    WebMock.disallow_net_connect!
  end

  def test_prod
    server, sdk = get_initialize_responses('https://statsigapi.net/v1')
    validate_consistency(server, sdk)
  end

  def test_prod_with_dev
    server, sdk = get_initialize_responses('https://statsigapi.net/v1', environment: { 'tier' => 'development' })
    validate_consistency(server, sdk)
  end

  def test_staging
    server, sdk = get_initialize_responses('https://staging.statsigapi.net/v1', hash: 'none')
    validate_consistency(server, sdk)
  end

  def test_djb2
    server, sdk = get_initialize_responses(
      'https://latest.statsigapi.net/v1',
      environment: { 'tier' => 'development' },
      hash: 'djb2'
    )
    validate_consistency(server, sdk)
  end

  def test_nil_result
    Statsig.initialize('secret-not-valid-key', StatsigOptions.new(local_mode: true))
    result = Statsig.get_client_initialize_response(StatsigUser.new(USER_HASH))
    assert_nil(result)
  end

  def test_fetch_from_server
    server, sdk = get_initialize_responses('https://statsigapi.net/v1', force_fetch_from_server: true)

    server.each_key do |key|
      next unless server[key].is_a?(Hash)
      next if %w[derived_fields param_stores].include?(key)

      server[key].each do |sub_key, _|
        sdk_value = sdk[key][sub_key]

        case key
        when 'feature_gates'
          assert_equal(false, sdk_value['value'], "Failed comparing #{key} -> #{sub_key}")
        when 'dynamic_configs', 'layer_configs'
          if sdk_value['is_in_layer'] != true
            assert_equal({}, sdk_value['value'], "Failed comparing #{key} -> #{sub_key}")
          end
        end
      end
      assert_equal(server[key].keys.sort, sdk[key].keys.sort)
    end
  end

  private

  def get_initialize_responses(api, environment: nil, force_fetch_from_server: false, hash: 'sha256')
    headers = {
      'STATSIG-API-KEY' => @client_key,
      'STATSIG-CLIENT-TIME' => (Time.now.to_f * 1000).to_i.to_s,
      'Content-Type' => 'application/json; charset=UTF-8',
      'User-Agent' => ''
    }
    http = HTTP.headers(headers).accept(:json)
    server_user_hash = Marshal.load(Marshal.dump(USER_HASH))
    if environment.nil? == false
      server_user_hash['statsigEnvironment'] = environment
    end
    response = http.post("#{api}/initialize",
                         body: JSON.generate({ user: server_user_hash, statsigMetadata: STATSIG_METADATA, hash: hash }))

    options = StatsigOptions.new(environment, api)
    Statsig.instance_variable_set('@shared_instance', nil)
    Statsig.initialize(@secret_key, options)

    if force_fetch_from_server
      mock_fetch_from_server
    end

    [
      JSON.parse(response),
      Statsig.get_client_initialize_response(StatsigUser.new(USER_HASH), hash: hash)
    ]
  end

  def validate_consistency(server_data, sdk_data)
    assert !server_data.nil?, 'Server data was nil'
    assert !sdk_data.nil?, 'SDK data was nil'

    server_data.keys.each do |key|
      next if %w[generator time company_lcut derived_fields param_stores].include?(key)

      if server_data[key].is_a?(Hash)
        assert(!sdk_data[key].nil?, "Failed asserting that #{key} exists in SDK response")
        assert_equal(server_data[key].keys.sort, sdk_data[key].keys.sort)

        server_data[key].each do |sub_key, _|
          server_value = rm_secondary_exposure_hashes(server_data[key][sub_key])
          sdk_value = rm_secondary_exposure_hashes(sdk_data[key][sub_key])
          if server_value.nil?
            assert_nil(sdk_value, "Failed comparing #{key} -> #{sub_key}")
          else
            assert_equal(server_value, sdk_value, "Failed comparing #{key} -> #{sub_key}")
          end
        end
      else
        assert_equal(sdk_data[key], server_data[key], "Failed comparing #{key}")
      end
    end
  end

  def rm_secondary_exposure_hashes(value)
    unless value.is_a?(Hash)
      return value
    end

    value['secondary_exposures']&.each do |entry|
      entry['gate'] = '__REMOVED_FOR_TEST__'
    end

    value['undelegated_secondary_exposures']&.each do |entry|
      entry['gate'] = '__REMOVED_FOR_TEST__'
    end

    value
  end

  def mock_fetch_from_server
    shared_instance = Statsig.instance_variable_get('@shared_instance')
    evaluator = shared_instance.instance_variable_get('@evaluator')
    evaluator.instance_eval do
      def eval_spec(_, _)
        'fetch_from_server'
      end
    end
  end
end
