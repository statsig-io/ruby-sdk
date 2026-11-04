require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'statsig'

CUSTOM_DCS_BASE = 'http://custom-proxy.example.com/v2'.freeze
STATSIG_CDN_BASE = 'https://api.statsigcdn.com/v2'.freeze
ORIGIN_DCS_BASE = 'https://api.statsig.com/v2'.freeze
FIRST_DCS_BASE = 'https://first-fallback.example.com/v2'.freeze
SECOND_DCS_BASE = 'https://second-fallback.example.com/v2'.freeze
THIRD_DCS_BASE = 'https://third-fallback.example.com/v2'.freeze

class TestSyncConfigFallback < BaseTest
  suite :TestSyncConfigFallback

  def setup
    super
    @cdn_call_count = 0
    @custom_call_count = 0
    @dcs_response = File.read("#{__dir__}/data/download_config_specs.json")
    @requests = []

    WebMock.enable!
    WebMock.disable_net_connect!

    stub_download_config_specs(STATSIG_CDN_BASE)
      .to_return do |req|
        @requests << req
        @cdn_call_count += 1
        { status: 200, body: @dcs_response, headers: { 'Content-Type' => 'application/json' } }
      end

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists')
      .to_return(status: 200, body: '{}')
    stub_request(:post, 'https://statsigapi.net/v1/log_event')
      .to_return(status: 200)
  end

  def teardown
    Statsig.shutdown rescue nil
    WebMock.reset!
    WebMock.disable!
    super
  end

  def stub_custom(status:, body: nil)
    stub_download_config_specs(CUSTOM_DCS_BASE)
      .to_return do |_req|
        @custom_call_count += 1
        { status: status, body: body || @dcs_response, headers: { 'Content-Type' => 'application/json' } }
      end
  end

  def custom_options(extra = {})
    StatsigOptions.new(
      download_config_specs_url: "#{CUSTOM_DCS_BASE}/download_config_specs/",
      fallback_to_statsig_api: true,
      disable_rulesets_sync: true,
      disable_idlists_sync: true,
      **extra
    )
  end

  def stub_endpoint(base, status:, body: @dcs_response)
    stub_download_config_specs(base).to_return do |req|
      @requests << req
      { status: status, body: body, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def fallback_url(base)
    "#{base}/download_config_specs/"
  end

  def test_no_fallback_when_primary_succeeds
    stub_custom(status: 200)
    Statsig.initialize(SDK_KEY, custom_options)

    assert_equal 1, @custom_call_count
    assert_equal 0, @cdn_call_count
  end

  def test_fallback_triggered_on_init_500
    stub_custom(status: 500)
    Statsig.initialize(SDK_KEY, custom_options)

    assert @cdn_call_count > 0, "Expected fallback to CDN on init failure but CDN was not called"
  end

  def test_no_fallback_when_option_false
    stub_custom(status: 500)
    options = StatsigOptions.new(
      download_config_specs_url: "#{CUSTOM_DCS_BASE}/download_config_specs/",
      fallback_to_statsig_api: false,
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    )
    Statsig.initialize(SDK_KEY, options)

    assert_equal 0, @cdn_call_count
  end

  def test_explicit_fallbacks_work_with_default_cdn_primary_and_stop_on_success
    stub_endpoint(STATSIG_CDN_BASE, status: 500)
    stub_endpoint(FIRST_DCS_BASE, status: 500)
    stub_endpoint(SECOND_DCS_BASE, status: 200, body: 'not json')
    stub_endpoint(ORIGIN_DCS_BASE, status: 200)
    stub_endpoint(THIRD_DCS_BASE, status: 200)

    options = StatsigOptions.new(
      download_config_specs_fallback_urls: [fallback_url(FIRST_DCS_BASE), fallback_url(SECOND_DCS_BASE), fallback_url(ORIGIN_DCS_BASE), fallback_url(THIRD_DCS_BASE)],
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    )
    Statsig.initialize(SDK_KEY, options)

    assert_equal [STATSIG_CDN_BASE, FIRST_DCS_BASE, SECOND_DCS_BASE, ORIGIN_DCS_BASE].map { |base| URI(base).host },
                 @requests.map { |request| request.uri.host }
    assert Statsig.get_initialization_details[:configSpecReady]
  end

  def test_explicit_list_wins_over_boolean_and_skips_primary_and_duplicate_urls
    stub_endpoint(STATSIG_CDN_BASE, status: 500)
    stub_endpoint(ORIGIN_DCS_BASE, status: 200)
    options = StatsigOptions.new(
      fallback_to_statsig_api: true,
      download_config_specs_fallback_urls: [fallback_url(STATSIG_CDN_BASE).chomp('/'), fallback_url(ORIGIN_DCS_BASE).chomp('/'), fallback_url(ORIGIN_DCS_BASE)],
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    )
    Statsig.initialize(SDK_KEY, options)

    assert_equal [URI(STATSIG_CDN_BASE).host, URI(ORIGIN_DCS_BASE).host], @requests.map { |request| request.uri.host }
    assert_equal [fallback_url(STATSIG_CDN_BASE), fallback_url(ORIGIN_DCS_BASE), fallback_url(ORIGIN_DCS_BASE)], options.download_config_specs_fallback_urls
  end

  def test_custom_primary_uses_only_explicit_fallbacks_in_order
    stub_endpoint(CUSTOM_DCS_BASE, status: 400)
    stub_endpoint(FIRST_DCS_BASE, status: 400)
    stub_endpoint(SECOND_DCS_BASE, status: 200)
    Statsig.initialize(SDK_KEY, custom_options(
      download_config_specs_fallback_urls: [fallback_url(FIRST_DCS_BASE), fallback_url(SECOND_DCS_BASE)]
    ))

    assert_equal [CUSTOM_DCS_BASE, FIRST_DCS_BASE, SECOND_DCS_BASE].map { |base| URI(base).host },
                 @requests.map { |request| request.uri.host }
    assert_equal 0, @cdn_call_count
  end

  def test_timeout_and_malformed_body_continue_to_next_fallback
    stub_endpoint(STATSIG_CDN_BASE, status: 400)
    stub_download_config_specs(FIRST_DCS_BASE).to_timeout
    stub_endpoint(SECOND_DCS_BASE, status: 200, body: '{}')
    stub_endpoint(ORIGIN_DCS_BASE, status: 200)
    options = StatsigOptions.new(
      download_config_specs_fallback_urls: [fallback_url(FIRST_DCS_BASE), fallback_url(SECOND_DCS_BASE), fallback_url(ORIGIN_DCS_BASE)],
      network_timeout: 1,
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    )
    Statsig.initialize(SDK_KEY, options)

    assert_requested :get, %r{first-fallback\.example\.com/v2/download_config_specs/}, times: 1
    assert_equal [URI(STATSIG_CDN_BASE).host, URI(SECOND_DCS_BASE).host, URI(ORIGIN_DCS_BASE).host], @requests.map { |request| request.uri.host }
    assert Statsig.get_initialization_details[:configSpecReady]
  end

  def test_empty_list_disables_legacy_fallback
    stub_custom(status: 500)
    Statsig.initialize(SDK_KEY, custom_options(download_config_specs_fallback_urls: []))

    assert_equal 1, @custom_call_count
    assert_equal 0, @cdn_call_count
    refute Statsig.get_initialization_details[:configSpecReady]
  end

  def test_legacy_boolean_does_not_retry_default_cdn_primary
    stub_endpoint(STATSIG_CDN_BASE, status: 500)
    Statsig.initialize(SDK_KEY, StatsigOptions.new(
      fallback_to_statsig_api: true,
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    ))

    assert_equal 1, @requests.length
  end

  def test_background_fallback_waits_five_failed_polls_and_preserves_since_time_and_headers
    options = StatsigOptions.new(
      download_config_specs_fallback_urls: [fallback_url(ORIGIN_DCS_BASE)],
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    )
    Statsig.initialize(SDK_KEY, options)
    initial_time = JSON.parse(@dcs_response)['time']
    @requests.clear
    stub_endpoint(STATSIG_CDN_BASE, status: 400)
    stub_endpoint(ORIGIN_DCS_BASE, status: 200)

    4.times { Statsig.sync_rulesets }
    assert_equal 0, @requests.count { |request| request.uri.host == URI(ORIGIN_DCS_BASE).host }
    Statsig.sync_rulesets

    assert_equal 5, @requests.count { |request| request.uri.host == URI(STATSIG_CDN_BASE).host }
    fallback_requests = @requests.select { |request| request.uri.host == URI(ORIGIN_DCS_BASE).host }
    assert_equal 1, fallback_requests.length
    request = fallback_requests.first
    assert_equal "sinceTime=#{initial_time}", request.uri.query
    assert_equal SDK_KEY, request.headers['Statsig-Api-Key']
    assert request.headers['Statsig-Sdk-Type']
    assert request.headers['Statsig-Sdk-Version']
  end

  def test_all_failed_fallbacks_keep_last_good_specs
    options = StatsigOptions.new(
      download_config_specs_fallback_urls: [fallback_url(FIRST_DCS_BASE), fallback_url(SECOND_DCS_BASE)],
      disable_rulesets_sync: true,
      disable_idlists_sync: true
    )
    driver = Statsig.initialize(SDK_KEY, options)
    store = driver.instance_variable_get(:@store)
    initial_time = store.last_config_sync_time
    assert store.has_config?('test_config')
    stub_endpoint(STATSIG_CDN_BASE, status: 400)
    stub_endpoint(FIRST_DCS_BASE, status: 500)
    stub_endpoint(SECOND_DCS_BASE, status: 200, body: '{}')

    5.times { Statsig.sync_rulesets }

    assert_equal initial_time, store.last_config_sync_time
    assert store.has_config?('test_config')
    assert_equal 1, @requests.count { |request| request.uri.host == URI(FIRST_DCS_BASE).host }
    assert_equal 1, @requests.count { |request| request.uri.host == URI(SECOND_DCS_BASE).host }
  end

  def test_fallback_triggered_during_background_sync
    original_threshold = Statsig::SpecStore::STATSIG_NETWORK_FALLBACK_THRESHOLD
    Statsig::SpecStore.send(:remove_const, :STATSIG_NETWORK_FALLBACK_THRESHOLD)
    Statsig::SpecStore.const_set(:STATSIG_NETWORK_FALLBACK_THRESHOLD, 1)

    # Neutralize the bounded background-sync retry so a failed sync registers immediately;
    # this test isolates the fallback-after-threshold path, which is independent of retries.
    original_retry_limit = Statsig::Network::CONFIG_SYNC_RETRY_LIMIT
    Statsig::Network.send(:remove_const, :CONFIG_SYNC_RETRY_LIMIT)
    Statsig::Network.const_set(:CONFIG_SYNC_RETRY_LIMIT, 0)

    begin
      stub_custom(status: 200)
      options = StatsigOptions.new(
        download_config_specs_url: "#{CUSTOM_DCS_BASE}/download_config_specs/",
        fallback_to_statsig_api: true,
        rulesets_sync_interval: 0.3,
        disable_idlists_sync: true
      )
      Statsig.initialize(SDK_KEY, options)
      cdn_after_init = @cdn_call_count

      WebMock.reset!
      WebMock.disable_net_connect!
      stub_download_config_specs(CUSTOM_DCS_BASE)
        .to_return { @custom_call_count += 1; { status: 500 } }
      stub_download_config_specs(STATSIG_CDN_BASE)
        .to_return do |_req|
          @cdn_call_count += 1
          { status: 200, body: @dcs_response, headers: { 'Content-Type' => 'application/json' } }
        end
      stub_request(:post, 'https://statsigapi.net/v1/get_id_lists')
        .to_return(status: 200, body: '{}')
      stub_request(:post, 'https://statsigapi.net/v1/log_event')
        .to_return(status: 200)

      sleep(0.7)

      assert @cdn_call_count > cdn_after_init,
             "Expected CDN to be called after bg sync failure, but cdn_call_count=#{@cdn_call_count}"
    ensure
      Statsig::SpecStore.send(:remove_const, :STATSIG_NETWORK_FALLBACK_THRESHOLD)
      Statsig::SpecStore.const_set(:STATSIG_NETWORK_FALLBACK_THRESHOLD, original_threshold)
      Statsig::Network.send(:remove_const, :CONFIG_SYNC_RETRY_LIMIT)
      Statsig::Network.const_set(:CONFIG_SYNC_RETRY_LIMIT, original_retry_limit)
    end
  end
end
