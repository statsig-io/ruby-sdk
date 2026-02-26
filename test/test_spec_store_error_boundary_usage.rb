require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class TestSpecStoreErrorBoundaryUsage < BaseTest
  suite :TestSpecStoreErrorBoundaryUsage

  def setup
    super
    WebMock.enable!
    @diagnostics = Statsig::Diagnostics.new
    @sdk_configs = Statsig::SDKConfigs.new
    @error_boundary = Statsig::ErrorBoundary.new('secret-key', false)
    @options = StatsigOptions.new
    @network = Statsig::Network.new('secret-key', @options)
    @logger = Statsig::StatsigLogger.new(@network, @options, @error_boundary, @sdk_configs)
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_process_specs_logs_to_error_boundary_on_invalid_key
    # This test ensures that when an invalid SDK key is detected in the response,
    # the error is correctly logged to the error boundary.
    # Before the fix, this would have raised a NoMethodError because it tried to call
    # @err_boundary instead of @error_boundary.

    invalid_response = {
      feature_gates: {},
      dynamic_configs: {},
      layer_configs: {},
      has_updates: true,
      time: 123,
      hashed_sdk_key_used: 'invalid-key-hash'
    }.to_json

    stub_request(:post, 'https://statsigapi.net/v1/sdk_exception').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200, body: '{}')
    stub_download_config_specs.to_return(status: 200, body: invalid_response)

    # SpecStore.new calls download_config_specs -> process_specs
    # We need to ensure that hashed_sdk_key_used in the response is NOT equal to djb2(@secret_key)
    # djb2('secret-key') is '110609353'

    store = Statsig::SpecStore.new(
      @network,
      @options,
      nil,
      @diagnostics,
      @error_boundary,
      @logger,
      'secret-key',
      @sdk_configs
    )

    # Verify that the exception was logged to the error boundary endpoint
    # The first call to log_exception for InvalidSDKKeyResponse will trigger the network request.
    # Subsequent calls with the same exception class will be ignored by ErrorBoundary unless force: true.
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', times: 1) do |req|
      body = JSON.parse(req.body)
      assert_equal('Statsig::InvalidSDKKeyResponse', body['exception'])
    end
  end
end
