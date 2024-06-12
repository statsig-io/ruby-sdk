require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class ErrorBoundaryTest < BaseTest
  suite :ErrorBoundaryTest

  def before_setup
    super
    stub_request(:post, 'https://statsigapi.net/v1/sdk_exception').to_return(status: 200)
  end

  def setup
    super
    WebMock.enable!
    @boundary = Statsig::ErrorBoundary.new("secret-key", false)
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_recovers_from_errors
    recovered = false
    @boundary.capture(recover: -> { recovered = true }) do
      raise "Bad"
    end

    assert(recovered)
  end

  def test_logs_to_correct_endpoint
    @boundary.capture() do 
      raise "Bad" 
    end
    meta = Statsig.get_statsig_metadata
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :headers => {
      "statsig-api-key" => 'secret-key',
      "statsig-sdk-type" => meta['sdkType'],
      "statsig-sdk-version" => meta['sdkVersion'],
      "statsig-sdk-language-version" => meta['languageVersion']
    }, :times => 1)
  end

  def test_logs_error_details
    err = RuntimeError.new("Bad")
    @boundary.capture() do
      raise err
    end
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1) do |req|
      body = JSON.parse(req.body)
      assert_equal("RuntimeError", body["exception"])
      assert(body["info"].include?(err.message))
      err.backtrace.each { |i|
        assert(body["info"].include?(i))
      }
    end
  end

  def test_logs_statsig_meta
    @boundary.capture() do
      raise "Bad"
    end
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1) do |req|
      body = JSON.parse(req.body)
      assert_equal(Statsig.get_statsig_metadata, body["statsigMetadata"])
    end
  end

  def test_does_not_log_dupes
    @boundary.capture() do 
      raise "Bad" 
    end
    @boundary.capture() do
      raise "Bad"
    end
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1)
  end

  def test_does_not_catch_intended
    assert_raises(Interrupt) { @boundary.capture() do raise Interrupt.new end }
    assert_raises(Statsig::UninitializedError) { @boundary.capture() do raise Statsig::UninitializedError.new end }
    assert_raises(Statsig::ValueError) { @boundary.capture() do raise Statsig::ValueError.new end }
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 0)
  end

  def test_returns_successful_result
    res = @boundary.capture() do
      return "success"
    end
    assert_equal("success", res)
  end

  def test_returns_recovered_result
    res = @boundary.capture(recover: -> { "recovered" }) do
      raise "Bad"
    end
    assert_equal("recovered", res)
  end

  def test_returns_nil_by_default
    res = @boundary.capture() do 
      raise "Bad"
    end
    assert_nil(res)
  end
end
