# typed: false

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'webmock/minitest'

class TestNetwork < Minitest::Test

  def initialize(param)
    super(param)
    @calls = 0
  end

  def status_lambda(req)
    @calls += 1
    res = 500
    if @calls > 2
      res = 200
    end
    return res
  end

  def setup
    WebMock.enable!
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_retries_succeed
    stub_request(:post, "https://statsigapi.net/v1/log_event").to_return(status: lambda { |req| status_lambda(req) }, body: "hello")

    options = StatsigOptions.new(local_mode: false)
    @net = Statsig::Network.new('secret-abc', options, 1)
    spy = Spy.on(@net, :post_helper).and_call_through

    res, _ = @net.post_helper('log_event', "{}", 5, 1)

    assert(spy.calls.size == 3) ## 500, 500, 200
    res.status.success?
    assert(res.status.success?)
  end

  def test_logs_statsig_headers
    stub_request(:post, "https://statsigapi.net/v1/log_event").to_return(status: 200)
    options = StatsigOptions.new(local_mode: false)
    net = Statsig::Network.new('secret-abc', options)
    net.post_helper('log_event', "{}", 5, 1)
    meta = Statsig.get_statsig_metadata
    assert_requested(:post, 'https://statsigapi.net/v1/log_event', :headers => {
      "statsig-api-key" => 'secret-abc',
      "statsig-sdk-type" => meta['sdkType'],
      "statsig-sdk-version" => meta['sdkVersion'],
    }, :times => 1)
  end

  def test_retry_until_out_of_retries
    stub_request(:post, "https://statsigapi.net/v1/log_event").to_raise(StandardError)

    options = StatsigOptions.new(local_mode: false)
    @net = Statsig::Network.new('secret-abc', options, 1)
    spy = Spy.on(@net, :post_helper).and_call_through

    res, e = @net.post_helper('log_event', "{}", 5, 1)
    assert(res.nil?)
    assert(spy.calls.size == 6)
    assert(!e.nil?)
  end
end
