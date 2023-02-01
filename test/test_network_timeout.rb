# typed: ignore
require 'minitest'
require 'minitest/autorun'
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

class TestNetworkTimeout < Minitest::Test

  def initialize(param)
    super(param)
    @calls = 0
  end

  def setup
    WebMock.enable!
  end

  def teardown
    super
    WebMock.disable!
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

  def test_network_timeout
    WebMock.allow_net_connect!
    start_server()
    options = StatsigOptions.new(nil, 'http://localhost:4567/v1', network_timeout: 1, local_mode: false)
    net = Statsig::Network.new('secret-abc', options, 0)
    start = Time.now
    net.post_helper('download_config_specs', '{}', 0, 0)
    stop = Time.now
    elapsed = stop - start
    assert(elapsed < MIN_DCS_REQUEST_TIME, "expected #{elapsed} < #{MIN_DCS_REQUEST_TIME}")
    assert(elapsed >= 1, "expected #{elapsed} >= 1")
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
    assert(elapsed >= MIN_DCS_REQUEST_TIME, "expected #{elapsed} >= #{MIN_DCS_REQUEST_TIME}")
    stop_server()
  end
end