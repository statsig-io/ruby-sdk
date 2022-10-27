# typed: false
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

  def test_retries_succeed
    stub_request(:post, "https://statsigapi.net/v1/log_event").to_return(status: lambda { |req| status_lambda(req) }, body: "hello")

    @net = Statsig::Network.new('secret-abc', 'https://statsigapi.net/v1/', false, 1)
    spy = Spy.on(@net, :post_helper).and_call_through

    res, _ = @net.post_helper('log_event', "{}", 5, 1)

    assert(spy.calls.size == 3) ## 500, 500, 200
    res.status.success?
    assert(res.status.success?)
  end

  def test_retry_until_out_of_retries
    stub_request(:post, "https://statsigapi.net/v1/log_event").to_raise(StandardError)

    @net = Statsig::Network.new('secret-abc', 'https://statsigapi.net/v1/', false, 1)
    spy = Spy.on(@net, :post_helper).and_call_through

    res, e = @net.post_helper('log_event', "{}", 5, 1)
    assert(res.nil?)
    assert(spy.calls.size == 6)
    assert(!e.nil?)
  end

  def teardown
    super
    WebMock.disable!
  end
end
