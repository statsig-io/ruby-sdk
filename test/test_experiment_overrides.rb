require_relative 'test_helper'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class StatsigExperimentOverridesTest < BaseTest
  suite :StatsigExperimentOverridesTest

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

  def teardown
    super
    Statsig.shutdown
  end

  def test_override_experiment_by_group_name_basic
    user = StatsigUser.new({ 'userID' => 'test_user_1' })
    
    # Override to Control group
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_equal('Control', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('2RamGsERWbWMIMnSfOlQuX', exp.rule_id)
    expected_value = { experiment_param: 'control', layer_param: true, second_layer_param: false }
    assert_equal(expected_value, exp.value)
  end

  def test_override_experiment_by_group_name_test_group
    user = StatsigUser.new({ 'userID' => 'test_user_2' })
    
    # Override to Test group
    Statsig.override_experiment_by_group_name('sample_experiment', 'Test')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_equal('Test', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)
    expected_value = { experiment_param: 'test', layer_param: true, second_layer_param: true }
    assert_equal(expected_value, exp.value)
  end

  def test_override_experiment_by_group_name_ignore_local_overrides
    user = StatsigUser.new({ 'userID' => 'test_user_1' })
    
    # Set override
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    
    # Get experiment with ignore_local_overrides
    exp = Statsig.get_experiment(
      user, 
      'sample_experiment', 
      Statsig::GetExperimentOptions.new(ignore_local_overrides: true)
    )
    
    # Should return original value, not override
    assert_equal('Test', exp.group_name)
    assert_equal('Bootstrap', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)
  end

  def test_override_experiment_by_group_name_clear_overrides
    user = StatsigUser.new({ 'userID' => 'test_user_4' })
    
    # Set override
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Control', exp.group_name)
    
    # Clear overrides
    Statsig.clear_experiment_overrides
    
    # Use a different user to avoid memoization
    user2 = StatsigUser.new({ 'userID' => 'test_user_7' })
    exp = Statsig.get_experiment(user2, 'sample_experiment')
    
    # Should return original value
    assert_equal('Test', exp.group_name)
    assert_equal('Bootstrap', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)
  end

  def test_override_experiment_by_group_name_nonexistent_group
    user = StatsigUser.new({ 'userID' => 'test_user_5' })
    
    # Override to non-existent group
    Statsig.override_experiment_by_group_name('sample_experiment', 'NonExistentGroup')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_equal('NonExistentGroup', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('sample_experiment:override', exp.rule_id)
    assert_equal({}, exp.value) # Empty value for non-existent group
  end

  def test_override_experiment_by_group_name_nonexistent_experiment
    user = StatsigUser.new({ 'userID' => 'test_user_6' })
    
    # Try to override non-existent experiment
    Statsig.override_experiment_by_group_name('nonexistent_experiment', 'Control')
    exp = Statsig.get_experiment(user, 'nonexistent_experiment')
    
    # Should return unrecognized result, not override
    assert_equal('Unrecognized', exp.evaluation_details&.reason)
    assert_equal({}, exp.value)
  end

  def test_override_experiment_by_group_name_multiple_experiments
    user = StatsigUser.new({ 'userID' => 'test_user_7' })
    
    # Override the same experiment multiple times
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    Statsig.override_experiment_by_group_name('sample_experiment', 'Test')
    
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_equal('Test', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)
    
    # Clear all overrides
    Statsig.clear_experiment_overrides
    
    # Use a different user to avoid memoization
    user2 = StatsigUser.new({ 'userID' => 'test_user_7_after_clear' })
    exp = Statsig.get_experiment(user2, 'sample_experiment')
    
    # Should return original values
    assert_equal('Test', exp.group_name)
    assert_equal('Bootstrap', exp.evaluation_details&.reason)
  end

  def test_override_experiment_by_group_name_case_sensitive
    user = StatsigUser.new({ 'userID' => 'test_user_8' })
    
    # Override with different case
    Statsig.override_experiment_by_group_name('sample_experiment', 'control')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    # Should not match 'Control' (case sensitive)
    assert_equal('control', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('sample_experiment:override', exp.rule_id)
    assert_equal({}, exp.value)
  end

  def test_override_experiment_by_group_name_empty_group_name
    user = StatsigUser.new({ 'userID' => 'test_user_9' })
    
    # Override with empty group name
    Statsig.override_experiment_by_group_name('sample_experiment', '')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_equal('', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('sample_experiment:override', exp.rule_id)
    assert_equal({}, exp.value)
  end

  def test_override_experiment_by_group_name_nil_group_name
    user = StatsigUser.new({ 'userID' => 'test_user_10' })
    
    # Override with nil group name
    Statsig.override_experiment_by_group_name('sample_experiment', nil)
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_nil(exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('sample_experiment:override', exp.rule_id)
    assert_equal({}, exp.value)
  end

  def test_override_experiment_by_group_name_dynamic_config
    user = StatsigUser.new({ 'userID' => 'test_user_11' })
    
    # Try to override a dynamic config (not an experiment)
    Statsig.override_experiment_by_group_name('test_config', 'Control')
    config = Statsig.get_config(user, 'test_config')
    
    # Should return normal config evaluation, not override
    assert_equal('Bootstrap', config.evaluation_details&.reason)
    refute_equal('Control', config.group_name)
  end

  def test_override_experiment_by_group_name_gate
    user = StatsigUser.new({ 'userID' => 'test_user_12' })
    
    # Try to override a gate (not an experiment)
    Statsig.override_experiment_by_group_name('always_on_gate', 'Control')
    gate = Statsig.check_gate(user, 'always_on_gate')
    
    # Should return normal gate evaluation, not override
    assert_equal(true, gate) # Gate should be on
  end

  def test_override_experiment_by_group_name_multiple_users
    user1 = StatsigUser.new({ 'userID' => 'user1' })
    user2 = StatsigUser.new({ 'userID' => 'user2' })
    
    # Override experiment
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    
    # Both users should get the same override
    exp1 = Statsig.get_experiment(user1, 'sample_experiment')
    exp2 = Statsig.get_experiment(user2, 'sample_experiment')
    
    assert_equal('Control', exp1.group_name)
    assert_equal('Control', exp2.group_name)
    assert_equal('LocalOverride', exp1.evaluation_details&.reason)
    assert_equal('LocalOverride', exp2.evaluation_details&.reason)
  end

  def test_override_experiment_by_group_name_override_changes
    user = StatsigUser.new({ 'userID' => 'test_user_13' })
    
    # Set initial override
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Control', exp.group_name)
    
    # Change override
    Statsig.override_experiment_by_group_name('sample_experiment', 'Test')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Test', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('2RamGujUou6h2bVNQWhtNZ', exp.rule_id)
  end

  def test_override_experiment_by_group_name_with_config_overrides
    user = StatsigUser.new({ 'userID' => 'test_user_14' })
    
    # Set config override
    Statsig.override_config('sample_experiment', { 'key' => 'config_override' })
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal({ 'key' => 'config_override' }, exp.value)
    
    # Set group override (should take precedence)
    Statsig.override_experiment_by_group_name('sample_experiment', 'Control')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal('Control', exp.group_name)
    expected_value = { experiment_param: 'control', layer_param: true, second_layer_param: false }
    assert_equal(expected_value, exp.value)
    
    # Clear experiment overrides
    Statsig.clear_experiment_overrides
    exp = Statsig.get_experiment(user, 'sample_experiment')
    assert_equal({ 'key' => 'config_override' }, exp.value)
  end

  def test_override_experiment_by_group_name_experiment_size_group
    user = StatsigUser.new({ 'userID' => 'test_user_15' })
    
    # Override to experimentSize group (which exists in the test data)
    Statsig.override_experiment_by_group_name('sample_experiment', 'experimentSize')
    exp = Statsig.get_experiment(user, 'sample_experiment')
    
    assert_equal('experimentSize', exp.group_name)
    assert_equal('LocalOverride', exp.evaluation_details&.reason)
    assert_equal('', exp.rule_id) # Empty rule ID for experimentSize group
    expected_value = { layer_param: true, second_layer_param: false }
    assert_equal(expected_value, exp.value)
  end
end 