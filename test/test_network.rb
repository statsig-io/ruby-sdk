require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'webmock/minitest'

class FakeHTTPBody
  attr_reader :read_count

  def initialize(body)
    @body = body
    @read_count = 0
  end

  def to_s
    @read_count += 1
    @body
  end
end

class FakeHTTPStatus
  attr_reader :code

  def initialize(code)
    @code = code
  end

  def success?
    @code >= 200 && @code < 300
  end

  def to_i
    @code
  end
end

class FakeHTTPResponse
  attr_reader :status, :headers, :body

  def initialize(code: 200, body: '{}', headers: {})
    @status = FakeHTTPStatus.new(code)
    @headers = headers
    @body = FakeHTTPBody.new(body)
  end

  def [](key)
    @headers[key]
  end

  def code
    @status.code
  end

  def to_s
    @body.to_s
  end
end

class FakeHTTPRequest
  def initialize(response_factory)
    @response_factory = response_factory
  end

  def get(_url)
    @response_factory.call
  end

  def post(_url, body: nil)
    @response_factory.call
  end
end

class FakeHTTPClient
  attr_reader :requests
  attr_accessor :closed

  def initialize(response_factory)
    @response_factory = response_factory
    @requests = []
    @closed = false
  end

  def headers(headers)
    @requests << headers.dup
    FakeHTTPRequest.new(@response_factory)
  end

  def close
    @closed = true
  end
end

class FakeHTTPBuilder
  attr_reader :timeout_values, :persistent_origins, :clients

  def initialize(&response_factory)
    @response_factory = response_factory
    @timeout_values = []
    @persistent_origins = []
    @clients = {}
  end

  def timeout(value)
    @timeout_values << value
    self
  end

  def persistent(origin)
    @persistent_origins << origin
    @clients[origin] ||= FakeHTTPClient.new(@response_factory)
  end
end

class TestNetwork < BaseTest
  suite :TestNetwork

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
    super
    WebMock.enable!
    stub_download_config_specs.to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def test_retries_succeed
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: lambda { |req| status_lambda(req) }, body: 'hello')

    options = StatsigOptions.new(local_mode: false)
    @net = Statsig::Network.new('secret-abc', options, 1)
    spy = Spy.on(@net, :request).and_call_through

    res, _ = @net.post('https://statsigapi.net/v1/log_event', '{}', 5, 1)

    assert(spy.calls.size == 3) ## 500, 500, 200
    res.status.success?
    assert(res.status.success?)
  end

  def test_logs_statsig_headers
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    options = StatsigOptions.new(local_mode: false)
    net = Statsig::Network.new('secret-abc', options)
    net.post('https://statsigapi.net/v1/log_event', '{}', 5, 1)
    meta = Statsig.get_statsig_metadata
    assert_requested(:post, 'https://statsigapi.net/v1/log_event', :headers => {
      'statsig-api-key' => 'secret-abc',
      'statsig-sdk-type' => meta['sdkType'],
      'statsig-sdk-version' => meta['sdkVersion'],
    }, :times => 1)
  end

  def test_retry_until_out_of_retries
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_raise(StandardError)

    options = StatsigOptions.new(local_mode: false)
    @net = Statsig::Network.new('secret-abc', options, 1)
    spy = Spy.on(@net, :request).and_call_through

    res, e = @net.post('https://statsigapi.net/v1/log_event', '{}', 5, 1)
    assert(res.nil?)
    assert(spy.calls.size == 6)
    assert(!e.nil?)
  end

  def test_discards_failed_connection_without_masking_error
    connection_error = IOError.new('broken connection')
    failed_builder = FakeHTTPBuilder.new { raise connection_error }
    builders = [failed_builder, FakeHTTPBuilder.new { FakeHTTPResponse.new }]

    HTTP.stub(:use, ->(_) { builders.shift }) do
      net = Statsig::Network.new('secret-abc', StatsigOptions.new(local_mode: false))
      failed_response, error = net.get('https://statsigapi.net/health')

      assert_nil(failed_response)
      assert_same(connection_error, error)
      assert(failed_builder.clients['https://statsigapi.net'].closed)

      response, error = net.get('https://statsigapi.net/health')

      assert_nil(error)
      assert(response.status.success?)
    ensure
      net&.shutdown
    end
  end

  def test_reuses_persistent_clients_per_origin_and_drains_response_bodies
    builder = FakeHTTPBuilder.new { FakeHTTPResponse.new }
    options = StatsigOptions.new(local_mode: false, network_timeout: 2)

    HTTP.stub(:use, builder) do
      net = Statsig::Network.new('secret-abc', options)

      log_response_1, = net.post('https://statsigapi.net/v1/log_event', '{}')
      log_response_2, = net.post('https://statsigapi.net/v1/log_event', '{}')
      dcs_response, = net.get('https://api.statsigcdn.com/v2/download_config_specs/secret-abc.json')

      assert_equal(1, builder.persistent_origins.count('https://statsigapi.net'))
      assert_equal(1, builder.persistent_origins.count('https://api.statsigcdn.com'))
      assert_equal(2, builder.clients['https://statsigapi.net'].requests.length)
      assert_equal(1, log_response_1.body.read_count)
      assert_equal(1, log_response_2.body.read_count)
      assert_equal(1, dcs_response.body.read_count)

      net.shutdown

      assert(builder.clients.values.all?(&:closed))
    end
  end

  def test_download_id_list_omits_statsig_auth_headers
    builder = FakeHTTPBuilder.new { FakeHTTPResponse.new(body: "+1\n", headers: { 'content-length' => '3' }) }
    options = StatsigOptions.new(local_mode: false)

    HTTP.stub(:use, builder) do
      net = Statsig::Network.new('secret-abc', options)
      response, error = net.download_id_list('https://statsigapi.net/ruby-test-idlist/list_1', 10)

      assert_nil(error)
      headers = builder.clients['https://statsigapi.net'].requests.last

      assert_equal('bytes=10-', headers['Range'])
      assert_nil(headers['STATSIG-API-KEY'])
      assert_nil(headers['Content-Type'])
      assert_equal(1, response.body.read_count)
    end
  end

  def test_ruleset_id_list_retries
    @calls = 0
    stub_download_config_specs.to_return(status: lambda { |req| status_lambda(req) }, body: '{}')
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: lambda { |req| status_lambda(req) }, body: '{}')

    options = StatsigOptions.new(local_mode: false, initialize_retry_limit: 2)
    net = Statsig::Network.new('secret-abc', options, 0.1)
    spy = Spy.on(net, :request).and_call_through

    # Test ruleset retries
    @calls = 0
    res, _ = net.download_config_specs(0, 'initialize')
    assert(spy.calls.size == 3) # 500, 500, 200
    assert(res.status.success?)

    # Test id list retries
    @calls = 0
    res, _ = net.get_id_lists('initialize')
    assert(spy.calls.size == 6) # 500, 500, 200
    assert(res.status.success?)
  end

  def test_config_sync_retries_succeed
    # Use a dedicated DCS url so a background sync thread lingering from another test
    # (the Statsig singleton) can't hit this stub and skew the attempt count.
    base = 'http://config-sync-retry.example/v2'
    attempts = 0
    stub_download_config_specs(base).to_return do |_req|
      attempts += 1
      { status: attempts < 3 ? 500 : 200, body: '{}' }
    end

    options = StatsigOptions.new(local_mode: false, download_config_specs_url: "#{base}/download_config_specs/")
    net = Statsig::Network.new('secret-abc', options)
    spy = Spy.on(net, :request).and_call_through

    res, _ = net.download_config_specs(0, 'config_sync')
    assert(res.status.success?) # recovers once the transient failures clear
    assert(spy.calls.size > 1, "expected config_sync to retry the transient failure, got #{spy.calls.size} attempt(s)")
  end

  def test_config_sync_retries_exhausted
    stub_download_config_specs.to_return(status: 500, body: '{}')

    options = StatsigOptions.new(local_mode: false)
    net = Statsig::Network.new('secret-abc', options)
    spy = Spy.on(net, :request).and_call_through

    res, e = net.download_config_specs(0, 'config_sync')
    # Fixed background retry budget: 1 initial attempt + CONFIG_SYNC_RETRY_LIMIT retries.
    assert(spy.calls.size == Statsig::Network::CONFIG_SYNC_RETRY_LIMIT + 1)
    assert(!res.status.success?)
    assert(!e.nil?)
  end
end
