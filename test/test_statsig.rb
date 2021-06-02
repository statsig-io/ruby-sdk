require 'minitest'
require 'minitest/autorun'
require 'statsig'

class TestStatsig < Minitest::Test
  def after_teardown
    super
    Statsig.shutdown
  end

  def test_a_secret_must_be_provided
    assert_raises { Statsig.initialize(nil) }
  end

  def test_an_empty_secret_will_fail
    assert_raises { Statsig.initialize('') }
  end

  def test_client_api_keys_will_fail
    assert_raises { Statsig.initialize('client') }
  end

  def test_check_gate_works
    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW')
    gate = Statsig.check_gate(StatsigUser.new, 'test_public')
    assert(gate == true)
  end

  def test_email_gate_works
    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW')
    statsig_user = StatsigUser.new
    statsig_user.email = "jkw@statsig.com"
    pass_gate = Statsig.check_gate(statsig_user, 'test_email')
    assert(pass_gate == true)

    non_statsig_user = StatsigUser.new
    non_statsig_user.email = "jkw@gmail.com"
    fail_gate = Statsig.check_gate(non_statsig_user, 'test_email')
    assert(fail_gate == false)
  end
end