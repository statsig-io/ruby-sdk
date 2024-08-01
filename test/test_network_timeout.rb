

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'sinatra/base'
require_relative 'mock_server'

class TestNetworkTimeout < BaseTest
  suite :TestNetworkTimeout
  def setup
    super
    WebMock.enable!
    WebMock.allow_net_connect!
    MockServer.start_server
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
    WebMock.disallow_net_connect!
    MockServer.stop_server
  end

  def test_network_timeout
    options = StatsigOptions.new(
      nil,
      network_timeout: 1,
      local_mode: false
    )
    net = Statsig::Network.new('secret-abc', options, 0)
    start = Time.now
    net.get('http://localhost:4567/v2/download_config_specs', 0, 0)
    stop = Time.now
    elapsed = stop - start
    assert(elapsed < MIN_DCS_REQUEST_TIME, "expected #{elapsed} < #{MIN_DCS_REQUEST_TIME}")
    assert(elapsed >= 1, "expected #{elapsed} >= 1")
  end

  def test_no_network_timeout
    options = StatsigOptions.new(nil, local_mode: false)
    net = Statsig::Network.new('secret-abc', options, 0)
    start = Time.now
    net.get('http://localhost:4567/v2/download_config_specs', 0, 0)
    stop = Time.now
    elapsed = stop - start
    assert(elapsed >= MIN_DCS_REQUEST_TIME, "expected #{elapsed} >= #{MIN_DCS_REQUEST_TIME}")
  end
end
