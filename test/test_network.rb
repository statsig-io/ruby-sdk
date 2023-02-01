# typed: ignore
require 'minitest'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'webmock/minitest'
require 'sinatra/base'

MIN_DCS_REQUEST_TIME = 3
# Lives on http://localhost:4567
class MockServer < Sinatra::Base
  post '/v1/download_config_specs' do
    sleep MIN_DCS_REQUEST_TIME
  end
end

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

  def start_server
    @thread = Thread.new do
      MockServer.run!
    end
    sleep 1
  end

  def stop_server
    MockServer.stop!
    @thread.kill
  end

  def setup
    WebMock.enable!
  end

  def teardown
    super
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

  def test_network_timeout
    WebMock.allow_net_connect!
    start_server()
    options = StatsigOptions.new(nil, 'http://localhost:4567/v1', network_timeout: 1, local_mode: false)
    net = Statsig::Network.new('secret-abc', options, 0)
    start = Time.now
    net.post_helper('download_config_specs', '{}', 0, 0)
    stop = Time.now
    elapsed = stop - start
    assert(elapsed < MIN_DCS_REQUEST_TIME)
    assert(elapsed >= 1)
    stop_server()
  end

  def test_no_network_timeout
    WebMock.allow_net_connect!
    start_server()
    options = StatsigOptions.new(nil, 'http://localhost:4567/v1', local_mode: false)
    net = Statsig::Network.new('secret-abc', options, 0)
    start = Time.now
    net.post_helper('download_config_specs', '{}', 0, 0)
    stop = Time.now
    elapsed = stop - start
    assert(elapsed >= MIN_DCS_REQUEST_TIME)
    stop_server()
  end
end
