require_relative 'test_helper'
require 'minitest/autorun'
require 'memo'

class MemoTest < BaseTest
  suite :MemoTest
  def test_for_memoizes_result
    hash = {}
    result = Statsig::Memo.for(hash, :test_method, :test_key) { 'value' }
    assert_equal 'value', result
    assert_equal 'value', hash[:test_method][:test_key]
  end

  def test_for_does_not_revaluate_if_memoized
    hash = { test_method: { test_key: 'cached_value' } }
    result = Statsig::Memo.for(hash, :test_method, :test_key) { flunk 'This should not be executed' }
    assert_equal 'cached_value', result
  end

  def test_for_global_memoizes_result
    Statsig::Memo.instance_variable_set(:@global_memo, {})
    result = Statsig::Memo.for_global(:test_method, :test_key) { 'global_value' }
    assert_equal 'global_value', result
    global_memo = Statsig::Memo.instance_variable_get(:@global_memo)
    assert_equal 'global_value', global_memo[:test_method][:test_key]
  end

  def test_for_global_does_not_revaluate_if_memoized
    Statsig::Memo.instance_variable_set(:@global_memo, { test_method: { test_key: 'global_cached' } })
    result = Statsig::Memo.for_global(:test_method, :test_key) { flunk 'This should not be executed' }
    assert_equal 'global_cached', result
  end

  def test_for_disables_memoization_when_option_set
    hash = {}
    result1 = Statsig::Memo.for(hash, :test_method, 0, disable_evaluation_memoization: true) { 42 }
    result2 = Statsig::Memo.for(hash, :test_method, 0, disable_evaluation_memoization: true) { 43 }
    assert_equal 42, result1
    assert_equal 43, result2
  end
end
