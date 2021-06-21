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

  def test_env_tier_gate_works
    Statsig.shutdown
    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW', StatsigOptions.new({'TIER' => 'development'}))
    pass_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), 'test_environment_tier')
    assert(pass_gate == true)
    Statsig.shutdown

    Statsig.shutdown
    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW', StatsigOptions.new({'tier' => 'development'}))
    pass_gate_2 = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), 'test_environment_tier')
    assert(pass_gate_2 == true)
    Statsig.shutdown

    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW', StatsigOptions.new({'tier' => 'production'}))
    fail_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), 'test_environment_tier')
    assert(fail_gate == false)
    Statsig.shutdown

    Statsig.initialize('secret-9IWfdzNwExEYHEW4YfOQcFZ4xreZyFkbOXHaNbPsMwW')
    fail_gate_2 = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), 'test_environment_tier')
    assert(fail_gate_2 == false)
    Statsig.shutdown
  end

  def test_half_pass_country_gate
    fail_gate = Statsig.check_gate(StatsigUser.new({'userID' => '123', 'country' => 'US'}), 'test_country_partial')
    assert(fail_gate == false)

    pass_gate = Statsig.check_gate(StatsigUser.new({'userID' => '4', 'country' => 'US'}), 'test_country_partial')
    assert(pass_gate == true)
  end

  def test_version_gate
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1'}), 'test_version') == true)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2'}), 'test_version') == true)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.3'}), 'test_version') == true)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.3.1'}), 'test_version') == true)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.3.3.9'}), 'test_version') == true)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2-alpha'}), 'test_version') == true)

    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '2'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.3'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.4'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.4-beta'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.3.4'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.3.10'}), 'test_version') == false)
    assert(Statsig.check_gate(StatsigUser.new({'userID' => '123', 'clientVersion' => '1.2.3.4.1'}), 'test_version') == false)
  end
end