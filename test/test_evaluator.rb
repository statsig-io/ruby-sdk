require 'minitest'
require 'minitest/autorun'
require 'statsig'

class TestEvaluator < Minitest::Test
  def setup
    super
    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW')
  end

  def test_check_gate_works
    gate = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), 'test_public')
    assert(gate == true)
  end

  def test_email_gate_works
    pass_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'email' => 'jkw@statsig.com'}), 'test_email')
    assert(pass_gate == true)

    fail_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'email' => 'jkw@gmail.com'}), 'test_email')
    assert(fail_gate == false)
  end

  def test_ip_gate_works
    pass_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'country' => 'US'}), 'test_country')
    assert(pass_gate == true)

    fail_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'country' => 'UK'}), 'test_country')
    assert(fail_gate == false)

    pass_gate_ip = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'ip' => '72.229.28.185'}), 'test_country')
    fail_gate_ip = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'ip' => '192.168.0.1'}), 'test_country')
    assert(pass_gate_ip == true)
    assert(fail_gate_ip == false)
  end
end