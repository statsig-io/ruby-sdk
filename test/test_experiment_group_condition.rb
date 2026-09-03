require_relative 'test_helper'
require 'minitest/autorun'
require 'statsig'
require 'spy'
require 'webmock/minitest'

class ExperimentGroupConditionTest < BaseTest
  suite :ExperimentGroupConditionTest

  IN_TEST_GROUP = { hidden_templates: %w[welcome rsvp] }.freeze
  DEFAULT_VALUE = { hidden_templates: [] }.freeze

  def setup
    super
    @json_file = File.read("#{__dir__}/data/download_config_specs_experiment_group.json")
    Statsig.initialize(
      SDK_KEY,
      StatsigOptions.new(
        bootstrap_values: @json_file,
        local_mode: true,
        disable_diagnostics_logging: true,
        logging_interval_seconds: 9999,
        disable_evaluation_memoization: true
      )
    )
  end

  def teardown
    super
    Statsig.shutdown
  end

  def test_matches_when_user_is_in_the_named_group
    config = Statsig.get_config(user('test_user'), 'automations_hidden_templates')

    assert_equal(IN_TEST_GROUP, config.value)
    assert_equal('expGroupRuleID', config.rule_id)
  end

  def test_returns_default_when_user_is_in_another_group
    config = Statsig.get_config(user('control_user'), 'automations_hidden_templates')

    assert_equal(DEFAULT_VALUE, config.value)
    assert_equal('default', config.rule_id)
  end

  def test_returns_default_when_user_matches_no_group
    config = Statsig.get_config(user('unassigned_user'), 'automations_hidden_templates')

    assert_equal(DEFAULT_VALUE, config.value)
    assert_equal('default', config.rule_id)
  end

  def test_console_override_on_the_parent_experiment_makes_the_rule_match
    # The forced-ID rule the Console emits at the top of the parent's rule list
    # pins this user to the Test group, so the child rule must match.
    parent = Statsig.get_experiment(user('forced_user'), 'parent_experiment')
    assert_equal('Test', parent.group_name)
    assert_equal('parent_experiment:userID:id_override', parent.rule_id)

    config = Statsig.get_config(user('forced_user'), 'automations_hidden_templates')
    assert_equal(IN_TEST_GROUP, config.value)
  end

  def test_sdk_local_override_on_the_parent_experiment_makes_the_rule_match
    Statsig.override_experiment_by_group_name('parent_experiment', 'Test')

    config = Statsig.get_config(user('control_user'), 'automations_hidden_templates')

    assert_equal(IN_TEST_GROUP, config.value)
  ensure
    Statsig.clear_experiment_overrides
  end

  def test_unknown_experiment_never_matches
    config = Statsig.get_config(user('test_user'), 'config_unknown_experiment')

    assert_equal(DEFAULT_VALUE, config.value)
    assert_equal('default', config.rule_id)
  end

  def test_empty_experiment_name_never_matches
    config = Statsig.get_config(user('test_user'), 'config_empty_experiment_name')

    assert_equal(DEFAULT_VALUE, config.value)
    assert_equal('default', config.rule_id)
  end

  def test_missing_experiment_name_never_matches
    config = Statsig.get_config(user('test_user'), 'config_missing_experiment_name')

    assert_equal(DEFAULT_VALUE, config.value)
    assert_equal('default', config.rule_id)
  end

  def test_self_referencing_experiment_falls_back_to_the_error_boundary
    # statsig-rust has no recursion guard on this path either. Ruby's error boundary
    # already rescues SystemStackError, so the process survives and the caller gets
    # an empty config instead of a crash.
    config = Statsig.get_experiment(user('test_user'), 'self_referencing_experiment')

    assert_equal({}, config.value)
  end

  def test_gates_resolve_the_condition_too
    assert_equal(true, Statsig.check_gate(user('test_user'), 'gate_on_experiment_group'))
    assert_equal(false, Statsig.check_gate(user('control_user'), 'gate_on_experiment_group'))
  end

  def test_logs_a_parent_experiment_exposure_and_no_secondary_exposure
    Statsig.get_config(user('test_user'), 'automations_hidden_templates')

    events = flush_and_capture_events

    assert_equal(2, events.size)

    parent_exposure = events[0]
    assert_equal('statsig::config_exposure', parent_exposure[:eventName])
    assert_equal('parent_experiment', parent_exposure[:metadata][:config])
    assert_equal('testRuleID', parent_exposure[:metadata][:ruleID])

    child_exposure = events[1]
    assert_equal('statsig::config_exposure', child_exposure[:eventName])
    assert_equal('automations_hidden_templates', child_exposure[:metadata][:config])
    assert_equal('expGroupRuleID', child_exposure[:metadata][:ruleID])
    assert_empty(child_exposure[:secondaryExposures])
  end

  def test_does_not_log_a_parent_exposure_when_exposures_are_disabled
    Statsig.get_config_with_exposure_logging_disabled(user('test_user'), 'automations_hidden_templates')

    assert_nil(flush_and_capture_events)
  end

  def test_client_initialize_response_does_not_resolve_the_condition
    response = Statsig.get_client_initialize_response(user('test_user'), hash: 'none')
    config = response[:dynamic_configs]['automations_hidden_templates']

    assert_equal({ hidden_templates: [] }, config[:value])
    assert_equal('default', config[:rule_id])
    assert_nil(flush_and_capture_events)
  end

  private

  def user(user_id)
    StatsigUser.new({ 'userID' => user_id })
  end

  def flush_and_capture_events
    driver = Statsig.instance_variable_get('@shared_instance')
    net = driver.instance_variable_get('@net')
    spy = Spy.on(net, :post_logs).and_return
    driver.instance_variable_get('@logger').shutdown
    spy.calls[0]&.args&.first
  end
end
