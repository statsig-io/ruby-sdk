require_relative 'test_helper'
require 'minitest/autorun'
require_relative '../lib/statsig_user' # Adjust the path to the file containing your class

class StatsigUserTest < BaseTest
  suite :UserTest

  def setup
    @user = StatsigUser.new({user_id: 'user_123'})
    @user.custom_ids = { 'customid' => 'custom_value' }
    @user.memo_timeout = 0.1
    @user.clear_memo # Ensure a clean state before each test
  end

  def test_get_memo
    # Initial check to confirm memo is empty
    assert_empty @user.get_memo

    # Set a value and check if it's memoized
    @user.instance_variable_set(:@memo, { key: 'value' })
    assert_equal({ key: 'value' }, @user.get_memo)

    # Wait to test memoization timeout
    sleep 0.2
    assert_empty @user.get_memo, 'Memo should be cleared after timeout'
  end

  def test_clear_memo
    @user.instance_variable_set(:@memo, { key: 'value' })
    @user.clear_memo
    assert_empty @user.instance_variable_get(:@memo), 'Memo should be empty after clearing'
    refute @user.instance_variable_get(:@dirty), '@dirty should be false after clearing'
  end

  def test_memo_cleared_after_modification
    assert_empty @user.get_memo
    @user.instance_variable_set(:@memo, { key: 'value' })
    assert_equal({ key: 'value' }, @user.get_memo)

    @user.user_id = '456'
    assert @user.instance_variable_get(:@dirty), 'Memo should be dirty after modification'
    assert_empty @user.get_memo, 'Memo should be cleared after modification'
  end

  def test_get_unit_id_with_string_type
    assert_nil @user.get_unit_id('nonexistent_id')
  end

  def test_get_unit_id_with_existing_key
    assert_equal 'custom_value', @user.get_unit_id('customid')
  end

  def test_get_unit_id_with_existing_key_lowercase
    assert_equal 'custom_value', @user.get_unit_id('CUSTOMID')
  end

  def test_get_unit_id_with_non_string_type
    assert_equal 'user_123', @user.get_unit_id(123)
  end

  def test_get_unit_id_with_special_constants
    assert_equal 'user_123', @user.get_unit_id(Statsig::Const::CML_USER_ID)
  end

  def test_user_key
    @user.user_id = '123'
    @user.custom_ids = {'key1' => 'value1', 'key2' => 'value2'}

    expected_key = '123,value1,value2'
    assert_equal expected_key, @user.user_key

    # Testing with different values
    @user.user_id = nil
    @user.custom_ids = {'key3' => 'value3'}
    expected_key = ',value3'
    assert_equal expected_key, @user.user_key

    # Test when both user_id and custom_ids are not set or empty
    @user.user_id = nil
    @user.custom_ids = {}
    expected_key = ','
    assert_equal expected_key, @user.user_key
  end
end
