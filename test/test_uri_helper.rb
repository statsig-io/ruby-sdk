require 'test_helper'

class TestURIHelper < BaseTest
  suite :TestURIHelper

  def setup
    super
    WebMock.enable!
    @dcs_counter = {
      default: 0,
      custom_base_url: 0,
      custom_dcs_url: 0
    }
    stub_download_config_specs.to_return do |req|
      @dcs_counter[:default] += 1
    end
    stub_request(:post, 'https://statsigapi.net/v1/log_event')
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists')
    stub_download_config_specs('https://custom_base_url').to_return do |req|
      @dcs_counter[:custom_base_url] += 1
    end
    stub_request(:post, 'https://custom_base_url/log_event')
    stub_request(:post, 'https://custom_base_url/get_id_lists')
    stub_download_config_specs('https://custom_dcs_url').to_return do |req|
      @dcs_counter[:custom_dcs_url] += 1
    end
    @diagnostics = Statsig::Diagnostics.new()
    @error_boundary = Statsig::ErrorBoundary.new('secret-key', false)
  end

  def teardown
    super
    Statsig.shutdown
    WebMock.reset!
    WebMock.disable!
  end

  def test_custom_api_url_base
    options = StatsigOptions.new(
      nil,
      download_config_specs_url: 'https://custom_base_url/download_config_specs',
      log_event_url: 'https://custom_base_url/log_event',
      get_id_lists_url: 'https://custom_base_url/get_id_lists',
      rulesets_sync_interval: 9999,
      idlists_sync_interval: 9999
    )
    net = Statsig::Network.new(SDK_KEY, options)
    spy = Spy.on(net, :request).and_call_through
    logger = Statsig::StatsigLogger.new(net, options, @error_boundary)
    store = Statsig::SpecStore.new(net, options, nil, @diagnostics, @error_boundary, logger, SDK_KEY)
    wait_for do
      spy.calls.size >= 2 # wait for both download_config_specs and get_id_lists
    end
    store.shutdown
    assert_equal(0, @dcs_counter[:default])
    assert_equal(1, @dcs_counter[:custom_base_url])
    assert_equal(0, @dcs_counter[:custom_dcs_url])
  end

  def test_custom_api_url_dcs
    options = StatsigOptions.new(
      download_config_specs_url: 'https://custom_dcs_url/download_config_specs',

      rulesets_sync_interval: 9999,
      idlists_sync_interval: 9999
    )
    net = Statsig::Network.new(SDK_KEY, options)
    spy = Spy.on(net, :request).and_call_through
    logger = Statsig::StatsigLogger.new(net, options, @error_boundary)
    store = Statsig::SpecStore.new(net, options, nil, @diagnostics, @error_boundary, logger, SDK_KEY)
    wait_for do
      spy.calls.size >= 2 # wait for both download_config_specs and get_id_lists
    end
    store.shutdown
    assert_equal(0, @dcs_counter[:default])
    assert_equal(0, @dcs_counter[:custom_base_url])
    assert_equal(1, @dcs_counter[:custom_dcs_url])
  end

  def test_custom_api_url_base_and_dcs
    options = StatsigOptions.new(
      nil,
      download_config_specs_url: 'https://custom_dcs_url/download_config_specs',
      log_event_url: 'https://custom_base_url/log_event',
      get_id_lists_url: 'https://custom_base_url/get_id_lists',
      rulesets_sync_interval: 9999,
      idlists_sync_interval: 9999
    )
    net = Statsig::Network.new(SDK_KEY, options)
    spy = Spy.on(net, :request).and_call_through
    logger = Statsig::StatsigLogger.new(net, options, @error_boundary)
    store = Statsig::SpecStore.new(net, options, nil, @diagnostics, @error_boundary, logger, SDK_KEY)
    wait_for do
      spy.calls.size >= 2 # wait for both download_config_specs and get_id_lists
    end
    store.shutdown
    assert_equal(0, @dcs_counter[:default])
    assert_equal(0, @dcs_counter[:custom_base_url])
    assert_equal(1, @dcs_counter[:custom_dcs_url])
  end

  def test_default_api_url
    options = StatsigOptions.new(rulesets_sync_interval: 9999, idlists_sync_interval: 9999)
    net = Statsig::Network.new(SDK_KEY, options)
    spy = Spy.on(net, :request).and_call_through
    logger = Statsig::StatsigLogger.new(net, options, @error_boundary)
    store = Statsig::SpecStore.new(net, options, nil, @diagnostics, @error_boundary, logger, SDK_KEY)
    wait_for do
      spy.calls.size >= 2 # wait for both download_config_specs and get_id_lists
    end
    store.shutdown
    assert_equal(1, @dcs_counter[:default])
    assert_equal(0, @dcs_counter[:custom_base_url])
    assert_equal(0, @dcs_counter[:custom_dcs_url])
  end
end
