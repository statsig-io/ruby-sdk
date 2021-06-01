require 'minitest'
require 'minitest/autorun'
require 'statsig'

class TestStatsig < Minitest::Test
  def before_setup
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

  def test_that_check_gate_works
    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW')
    gate = Statsig.check_gate(StatsigUser.new, 'test_public')
    assert(gate == true)
  end
end