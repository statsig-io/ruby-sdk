

require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'

require 'statsig'

class UserFieldsTest < BaseTest
  suite :UserFieldsTest
  def test_nil_init
    a = nil
    user = StatsigUser.new(a)

    assert_nil(user.user_id)
    assert_nil(user.email)
    assert_nil(user.ip)
    assert_nil(user.user_agent)
    assert_nil(user.country)
    assert_nil(user.locale)
    assert_nil(user.app_version)
    assert_nil(user.custom)
    assert_nil(user.private_attributes)
    assert_nil(user.custom_ids)
    assert_nil(user.statsig_environment)
  end

  def test_init_with_different_hashes
    hashes = [
      {
        userID: 'a_user',
        email: 'a-user@mail.io',
        ip: '1.2.3.4',
        user_agent: 'Firefox/47.0',
        country: 'NZ',
        locale: 'en_US',
        app_version: '3.2.1',
        custom: { is_new: false, level: 2 },
        private_attributes: { secret_info: "shh" },
        custom_ids: { work_id: 'an-employee' },
        statsig_environment: { tier: 'production' }
      },
      {
        :userID => 'a_user',
        :email => 'a-user@mail.io',
        :ip => '1.2.3.4',
        :user_agent => 'Firefox/47.0',
        :country => 'NZ',
        :locale => 'en_US',
        :app_version => '3.2.1',
        :custom => { :is_new => false, :level => 2 },
        :private_attributes => { :secret_info => "shh" },
        :custom_ids => { :work_id => 'an-employee' },
        :statsig_environment => { :tier => 'production' }
      },
      {
        :user_id => 'a_user',
        :email => 'a-user@mail.io',
        :ip => '1.2.3.4',
        :userAgent => 'Firefox/47.0',
        :country => 'NZ',
        :locale => 'en_US',
        :appVersion => '3.2.1',
        :custom => { :is_new => false, :level => 2 },
        :privateAttributes => { :secret_info => "shh" },
        :customIDs => { :work_id => 'an-employee' },
        :statsigEnvironment => { :tier => 'production' }
      },
      {
        "user_id" => 'a_user',
        "email" => 'a-user@mail.io',
        "ip" => '1.2.3.4',
        "userAgent" => 'Firefox/47.0',
        "country" => 'NZ',
        "locale" => 'en_US',
        "appVersion" => '3.2.1',
        "custom" => { :is_new => false, :level => 2 },
        "privateAttributes" => { :secret_info => "shh" },
        "customIDs" => { :work_id => 'an-employee' },
        "statsigEnvironment" => { :tier => 'production' }
      },
    ]

    runs = 0
    hashes.each do |user_hash|
      user = StatsigUser.new(user_hash)
      runs += 1
      assert_equal("a_user", user.user_id)
      assert_equal("a-user@mail.io", user.email)
      assert_equal("1.2.3.4", user.ip)
      assert_equal("Firefox/47.0", user.user_agent)
      assert_equal("NZ", user.country)
      assert_equal("en_US", user.locale)
      assert_equal("3.2.1", user.app_version)
      assert_equal({ "is_new" => false, "level" => 2 }, user.custom)
      assert_equal({ "secret_info" => "shh" }, user.private_attributes)
      assert_equal({ "work_id" => 'an-employee' }, user.custom_ids)
      assert_equal({ "tier" => 'production' }, user.statsig_environment)
    end

    assert_equal(hashes.length, runs)
  end

  def test_init_with_invalid_types
    user = StatsigUser.new(
      {
        user_id: 1,
        email: 2,
        ip: 3,
        user_agent: 4,
        country: 5,
        locale: 6,
        app_version: 7,
        custom: 8,
        private_attributes: 9,
        custom_ids: 10,
        statsig_environment: 11
      })

    assert_nil(user.user_id)
    assert_nil(user.email)
    assert_nil(user.ip)
    assert_nil(user.user_agent)
    assert_nil(user.country)
    assert_nil(user.locale)
    assert_nil(user.app_version)
    assert_nil(user.custom)
    assert_nil(user.private_attributes)
    assert_nil(user.custom_ids)
    assert_nil(user.statsig_environment)
  end

  def test_various_primitives_from_hash
    user = StatsigUser.new(
      {
        userID: "a-user",
        custom:
          {
            a_string: "a_string_value",
            a_bool: true,
            an_int: 123,
            a_double: 4.56,
            an_array: [1, 2, 3],
            an_object: { key: "value" }
          }
      })

    custom = T.must(user.custom)

    assert_equal("a_string_value", custom["a_string"])
    assert_equal(true, custom["a_bool"])
    assert_equal(123, custom["an_int"])
    assert_equal(4.56, custom["a_double"])
    assert_equal([1, 2, 3], custom["an_array"])
    assert_equal({ "key" => "value" }, custom["an_object"])
  end

  def test_serializing
    user = StatsigUser.new(
      {
        user_id: 'a_user',
        email: 'a-user@mail.io',
        ip: '1.2.3.4',
        user_agent: 'Firefox/47.0',
        country: 'NZ',
        locale: 'en_US',
        app_version: '3.2.1',
        custom: { is_new: false },
        private_attributes: { secret_info: "shh" },
        custom_ids: { work_id: 'an-employee' },
        statsig_environment: { tier: 'production' }
      }
    )

    assert_equal(
      JSON.generate({ 'user' => {
        'userID' => 'a_user',
        'email' => 'a-user@mail.io',
        'ip' => '1.2.3.4',
        'userAgent' => 'Firefox/47.0',
        'country' => 'NZ',
        'locale' => 'en_US',
        'appVersion' => '3.2.1',
        'custom' => { is_new: false },
        'statsigEnvironment' => { tier: 'production' },
        'privateAttributes' => { secret_info: "shh" },
        'customIDs' => { work_id: 'an-employee' }
      } }),
      JSON.generate({ 'user' => user.serialize(false) }))
  end
end