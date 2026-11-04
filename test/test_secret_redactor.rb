require_relative 'test_helper'
require 'uri'

class SecretRedactorTest < BaseTest
  suite :SecretRedactorTest

  def setup
    super
    WebMock.enable!
  end

  def teardown
    WebMock.reset!
    WebMock.disable!
    super
  end

  def test_scrubs_raw_encoded_json_and_unknown_dcs_paths
    key = 'secret-a+!/z'
    encoded = URI.encode_www_form_component(key)
    redactor = Statsig::SecretRedactor.new(key)
    text = "#{key} #{encoded} #{key} https://example.test/v1/download_config_specs/other-key.json?sinceTime=1"
    result = redactor.text(text)
    refute_includes result, key
    refute_includes result, encoded
    assert_includes result, '/download_config_specs/[REDACTED].json?sinceTime=1'
    assert_includes result, 'example.test'
  end

  def test_sanitized_exception_retains_class_without_raw_cause_or_ivars
    redactor = Statsig::SecretRedactor.new('secret-short')
    original = nil
    begin
      begin
        raise 'secret-short nested'
      rescue
        raise ArgumentError, 'request secret-short failed'
      end
    rescue => e
      original = e
    end
    original.instance_variable_set(:@url, 'secret-short')
    original.set_backtrace(['request secret-short line 9'])
    safe = redactor.exception(original)
    assert_instance_of ArgumentError, safe
    assert_nil safe.cause
    assert_empty safe.instance_variables
    refute_includes safe.message, 'secret-short'
    refute_includes safe.backtrace.join, 'secret-short'
    assert_includes original.message, 'secret-short'
    refute_nil original.cause
  end

  def test_http_failure_redacts_key_but_request_retains_it
    key = 'secret-abc123'
    url = 'https://example.test/v1/download_config_specs/'
    stub_request(:get, "#{url}#{key}.json").to_return(status: 403, body: "failure #{key}")
    net = Statsig::Network.new(key, StatsigOptions.new(download_config_specs_url: url))
    _response, error = net.download_config_specs(0, 'initialize')
    assert_instance_of Statsig::NetworkError, error
    assert_equal 403, error.http_code
    refute_includes error.message, key
    assert_requested :get, "#{url}#{key}.json", times: 1
  ensure
    net&.shutdown
  end

  def test_http_statuses_and_fallback_paths_preserve_status
    key = 'secret-abc123'
    options = StatsigOptions.new(download_config_specs_url: 'https://custom.example/v2/download_config_specs/')
    net = Statsig::Network.new(key, options)
    [401, 403, 429, 503].each do |status|
      url = "https://custom.example/v2/download_config_specs/#{key}.json"
      stub_request(:get, url).to_return(status: status, body: "body #{key}")
      _, error = net.download_config_specs(0, 'initialize')
      assert_instance_of Statsig::NetworkError, error
      assert_equal status, error.http_code
      refute_includes error.message, key
      assert_includes error.message, 'custom.example'
    end
    fallback = "#{Statsig::STATSIG_CDN_DCS_BASE}/download_config_specs/#{key}.json"
    stub_request(:get, fallback).to_return(status: 403, body: key)
    _, error = net.download_config_specs_fallback(0, 'initialize')
    assert_equal 403, error.http_code
    refute_includes error.message, key
    assert_requested :get, fallback, times: 1
  ensure
    net&.shutdown
  end

  def test_connection_exception_is_copied_and_redacted
    key = 'secret-abc123'
    url = "https://example.test/v1/download_config_specs/#{key}.json"
    original = HTTP::TimeoutError.new("timeout for #{url}")
    original.set_backtrace(["network/#{key}:42"])
    stub_request(:get, url).to_raise(original)
    net = Statsig::Network.new(key, StatsigOptions.new(download_config_specs_url: 'https://example.test/v1/download_config_specs/'))
    _response, error = net.download_config_specs(0, 'initialize')
    assert_kind_of HTTP::TimeoutError, error
    refute_includes error.message, key
    refute_includes error.backtrace.join, key
    assert_nil error.cause
    assert_includes original.message, key
    assert_requested :get, url, times: 1
  ensure
    net&.shutdown
  end

  def test_exception_reporting_scrubs_message_trace_and_nested_extras
    key = 'secret-abc123'
    boundary = Statsig::ErrorBoundary.new(key)
    err = RuntimeError.new("failure #{key}")
    err.set_backtrace(["somewhere/#{key}:42"])
    stub_request(:post, 'https://statsigapi.net/v1/sdk_exception').to_return(status: 200)
    boundary.log_exception(err, tag: key, extra: { context: [key, { again: key }] })
    assert_requested :post, 'https://statsigapi.net/v1/sdk_exception', times: 1 do |req|
      refute_includes req.body, key
      assert_includes req.body, '[REDACTED]'
      assert_equal key, req.headers['Statsig-Api-Key']
      true
    end
  end
end
