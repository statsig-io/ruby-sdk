require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class StatsigLocalOverridesTest < BaseTest
  suite :StatsigLocalOverridesTest

  def setup
    super
    @json_file = File.read("#{__dir__}/data/download_config_specs.json")
    Statsig.initialize(
      'secret-key',
      StatsigOptions.new(
        bootstrap_values: @json_file,
        local_mode: true,
        disable_evaluation_memoization: true
      )
    )
  end

  def error_callback(e)
    puts e
    assert(false) # force fail if this is called
  end

  def teardown
    super
    Statsig.shutdown
  end

  def test_gates
    val = Statsig.check_gate(StatsigUser.new({ 'userID' => 'some_user_id' }), "override_me")
    assert(val == false)

    Statsig.override_gate("override_me", true)
    val = Statsig.check_gate(StatsigUser.new({ 'userID' => 'some_user_id' }), "override_me")
    assert(val == true)

    val = Statsig.check_gate(StatsigUser.new({ 'userID' => '123' }), "override_me")
    assert(val == true)

    val = Statsig.check_gate(
      StatsigUser.new({ 'userID' => '123' }), "override_me",
      Statsig::CheckGateOptions.new(ignore_local_overrides: true)
    )
    assert(val == false)

    Statsig.override_gate("override_me_2", true)
    Statsig.remove_gate_override("override_me")
    val = Statsig.check_gate(StatsigUser.new({ 'userID' => '123' }), "override_me")
    assert(val == false)
    val = Statsig.check_gate(StatsigUser.new({ 'userID' => '123' }), "override_me_2")
    assert(val == true)

    Statsig.clear_gate_overrides
    val = Statsig.check_gate(StatsigUser.new({ 'userID' => '123' }), "override_me_2")
    assert(val == false)
  end

  def test_configs
    val = Statsig.get_config(StatsigUser.new({ 'userID' => 'some_user_id' }), "override_me")
    assert(val.group_name.nil?)
    assert(val.value == {})

    Statsig.override_config("override_me", { "hello" => "its me" })
    val = Statsig.get_config(StatsigUser.new({ 'userID' => 'some_user_id' }), "override_me")
    assert(val.group_name.nil?)
    assert(val.value == { "hello" => "its me" })

    Statsig.override_config("override_me", { "hello" => "its no longer me" })
    val = Statsig.get_config(StatsigUser.new({ 'userID' => '123' }), "override_me")
    assert(val.group_name.nil?)
    assert(val.value == { "hello" => "its no longer me" })

    val = Statsig.get_config(
      StatsigUser.new({ 'userID' => '123' }), "override_me",
      Statsig::GetConfigOptions.new(ignore_local_overrides: true)
    )
    assert(val.group_name.nil?)
    assert(val.value == {})

    Statsig.override_config("override_me", {})
    val = Statsig.get_config(StatsigUser.new({ 'userID' => '123' }), "override_me")
    assert(val.group_name.nil?)
    assert(val.value == {})

    Statsig.override_config("override_me_2", { "hello" => "its me again" })
    Statsig.remove_config_override("override_me")
    val = Statsig.get_config(StatsigUser.new({ 'userID' => '123' }), "override_me")
    assert(val.group_name.nil?)
    assert(val.value == {})
    val = Statsig.get_config(StatsigUser.new({ 'userID' => '123' }), "override_me_2")
    assert(val.group_name.nil?)
    assert(val.value == { "hello" => "its me again" })

    Statsig.clear_config_overrides
    val = Statsig.get_config(StatsigUser.new({ 'userID' => '123' }), "override_me_2")
    assert(val.group_name.nil?)
    assert(val.value == {})
  end

  def test_override_experiment_by_group_name
    user = StatsigUser.new({ 'userID' => 'test_user' })
    exp = Statsig.get_experiment(user, 'sample_experiment')

    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Control', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('2RamGsERWbWMIMnSfOlQuX', exp.rule_id)

    Statsig.override_experiment_by_group_name('sample_experiment', 'Test')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Test', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)

    exp = Statsig.get_experiment(user, 'sample_experiment', Statsig::GetExperimentOptions.new(ignore_local_overrides: true))
    assert_equal('Test', exp.group_name)
    assert_equal('Bootstrap', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)

    Statsig.clear_experiment_overrides
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Test', exp.group_name)
    assert_equal('Bootstrap', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)
  end
end
