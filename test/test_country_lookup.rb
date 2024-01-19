# typed: false

require_relative 'test_helper'
require 'minitest'
require 'evaluator'
require 'statsig'
require 'country_lookup'

class CountryLookupTest < BaseTest
  suite :CountryLookupTest
  def setup
    CountryLookup.teardown
  end

  def test_initialize_async
    assert(CountryLookup.is_ready_for_lookup == false)
    bg_thread = CountryLookup.initialize_async
    bg_thread.join
    assert(CountryLookup.is_ready_for_lookup == true)
    assert(!bg_thread.alive?)
  end

  def test_no_race_condition
    bg_thread1 = CountryLookup.initialize_async
    assert(bg_thread1.alive?)
    bg_thread2 = CountryLookup.initialize_async
    assert(bg_thread2.alive?)
    assert_equal(bg_thread1, bg_thread2)
    CountryLookup.initialize
    assert(!bg_thread1.alive?)
  end

  def test_early_access
    assert(CountryLookup.is_ready_for_lookup == false)
    bg_thread = CountryLookup.initialize_async
    CountryLookup.lookup_ip_string('12345')
    assert(CountryLookup.is_ready_for_lookup == true)
    assert(!bg_thread.alive?)
  end

  def test_lookup
    WebMock.allow_net_connect!
    secret = ENV['test_api_key']
    Statsig.initialize(secret)
    user1 = StatsigUser.new({ user_id: '123', ip: '24.18.183.148' }) # Seattle, WA
    user2 = StatsigUser.new({ user_id: '123', ip: '115.240.90.163' }) # Mumbai, India (IN)
    assert(Statsig.check_gate(user1, 'test_country'))
    assert(Statsig.check_gate(user2, 'test_country') == false)
    Statsig.shutdown
    WebMock.disallow_net_connect!
  end
end
