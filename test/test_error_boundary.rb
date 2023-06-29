require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class ErrorBoundaryTest < Minitest::Test

  def before_setup
    super
    stub_request(:post, 'https://statsigapi.net/v1/sdk_exception').to_return(status: 200)
  end

  def setup
    WebMock.enable!
    @boundary = Statsig::ErrorBoundary.new("secret-key")
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_recovers_from_errors
    recovered = false
    @boundary.capture(task: -> {
      raise "Bad"
    }, recover: -> {
      recovered = true
    })

    assert(recovered)
  end

  def test_logs_to_correct_endpoint
    @boundary.capture(task: -> { raise "Bad" }, recover: -> {})
    meta = Statsig.get_statsig_metadata
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :headers => {
      "statsig-api-key" => 'secret-key',
      "statsig-sdk-type" => meta['sdkType'],
      "statsig-sdk-version" => meta['sdkVersion'],
    }, :times => 1)
  end

  def test_logs_error_details
    err = RuntimeError.new("Bad")
    @boundary.capture(task: -> { raise err }, recover: -> {})
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
    @boundary.capture(task: -> { raise "Bad" }, recover: -> {})
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1) do |req|
      body = JSON.parse(req.body)
      assert_equal(Statsig.get_statsig_metadata, body["statsigMetadata"])
    end
  end

  def test_does_not_log_dupes
    @boundary.capture(task: -> { raise "Bad" }, recover: -> {})
    @boundary.capture(task: -> { raise "Bad" }, recover: -> {})
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1)
  end

  def test_does_not_catch_intended
    assert_raises(Interrupt) { @boundary.capture(task: -> { raise Interrupt.new }, recover: -> {}) }
    assert_raises(Statsig::UninitializedError) { @boundary.capture(task: -> { raise Statsig::UninitializedError.new }, recover: -> {}) }
    assert_raises(Statsig::ValueError) { @boundary.capture(task: -> { raise Statsig::ValueError.new }, recover: -> {}) }
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 0)
  end

  def test_returns_successful_result
    res = @boundary.capture(task: -> {
      return "success"
    }, recover: -> {})
    assert_equal("success", res)
  end

  def test_returns_recovered_result
    res = @boundary.capture(task: -> {
      raise "Bad"
    }, recover: -> {
      return "recovered"
    })
    assert_equal("recovered", res)
  end

  def test_returns_nil_by_default
    res = @boundary.capture(task: -> { raise "Bad" })
    assert_nil(res)
  end
end