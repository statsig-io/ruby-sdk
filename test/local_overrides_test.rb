require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class StatsigE2ETest < Minitest::Test

  def setup
    super
    options = StatsigOptions.new()
    options.local_mode = true
    Statsig.initialize("secret-local", options)
  end

  def teardown
    super
    Statsig.shutdown
  end

  def test_gates
    val = Statsig.check_gate(StatsigUser.new({'userID' => 'some_user_id'}), "override_me")
    assert(val == false)

    Statsig.override_gate("override_me", true)
    val = Statsig.check_gate(StatsigUser.new({'userID' => 'some_user_id'}), "override_me")
    assert(val == true)

    val = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), "override_me")
    assert(val == true)

    Statsig.override_gate("override_me", false)
    val = Statsig.check_gate(StatsigUser.new({'userID' => '123'}), "override_me")
    assert(val == false)
  end

  def test_configs
    val = Statsig.get_config(StatsigUser.new({'userID' => 'some_user_id'}), "override_me")
    assert(val.value == {})

    Statsig.override_config("override_me", { "hello" => "its me" })
    val = Statsig.get_config(StatsigUser.new({'userID' => 'some_user_id'}), "override_me")
    assert(val.value == { "hello" => "its me" })

    Statsig.override_config("override_me", { "hello" => "its no longer me" })
    val = Statsig.get_config(StatsigUser.new({'userID' => '123'}), "override_me")
    assert(val.value == { "hello" => "its no longer me" })

    Statsig.override_config("override_me", {})
    val = Statsig.get_config(StatsigUser.new({'userID' => '123'}), "override_me")
    assert(val.value == {})
  end
end