# typed: true

require_relative 'test_helper'
require 'minitest'
require 'evaluator'

class CountryLookupTest < Minitest::Test
  def test_initialize_async
    bg_thread = CountryLookup.initialize_async
    assert(bg_thread.alive?)
    assert(CountryLookup.is_ready_for_lookup == false)
    sleep 1
    assert(!bg_thread.alive?)
    assert(CountryLookup.is_ready_for_lookup == true)
  end

  def test_no_race_condition
    bg_thread1 = CountryLookup.initialize_async
    assert(bg_thread1.alive?)
    bg_thread2 = CountryLookup.initialize_async
    assert(!bg_thread1.alive?)
    assert(bg_thread2.alive?)
    CountryLookup.initialize
    assert(!bg_thread2.alive?)
  end

  def test_early_access
    bg_thread = CountryLookup.initialize_async
    assert(CountryLookup.is_ready_for_lookup == false)
    CountryLookup.lookup_ip_string('12345')
    assert(CountryLookup.is_ready_for_lookup == true)
    assert(!bg_thread.alive?)
  end
end
