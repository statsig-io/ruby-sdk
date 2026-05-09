require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'statsig'

CUSTOM_DCS_BASE = 'http://custom-proxy.example.com/v2'.freeze
STATSIG_CDN_BASE = 'https://api.statsigcdn.com/v2'.freeze

class TestSyncConfigFallback < BaseTest
  suite :TestSyncConfigFallback

  def setup
    super
    @cdn_call_count = 0
    @custom_call_count = 0
    @dcs_response = File.read("#{__dir__}/data/download_config_specs.json")

    WebMock.enable!
    WebMock.disable_net_connect!

    stub_download_config_specs(STATSIG_CDN_BASE)
      .to_return do |_req|
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

  def test_fallback_triggered_during_background_sync
    original_threshold = Statsig::SpecStore::STATSIG_NETWORK_FALLBACK_THRESHOLD
    Statsig::SpecStore.send(:remove_const, :STATSIG_NETWORK_FALLBACK_THRESHOLD)
    Statsig::SpecStore.const_set(:STATSIG_NETWORK_FALLBACK_THRESHOLD, 1)

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
    end
  end
end