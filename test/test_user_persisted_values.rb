require_relative 'test_helper'
require 'interfaces/user_persistent_storage'

class TestUserPersistedValues < BaseTest
  suite :TestUserPersistedValues

  def setup
    @json_file = File.read("#{__dir__}/data/download_config_specs_sticky_experiments.json")
    @user_in_control = StatsigUser.new({ 'userID' => 'vj' })
    @user_in_test = StatsigUser.new({ 'userID' => 'hunter2' })
    @user_not_in_exp = StatsigUser.new({ 'userID' => 'gb' })

  end

  def teardown
    Statsig.shutdown
  end

  def test_valid_storage_adapter
    persistent_storage_adapter = DummyPersistentStorageAdapter.new
    spy_on_save = Spy.on(persistent_storage_adapter, :save).and_call_through
    Statsig.initialize(
      'secret-key',
      StatsigOptions.new(
        bootstrap_values: @json_file,
        user_persistent_storage: persistent_storage_adapter,
        local_mode: true
      )
    )

    # Control group
    exp = Statsig.get_experiment(@user_in_control, 'the_allocated_experiment')
    assert_equal('Control', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)

    # Test group
    exp = Statsig.get_experiment(@user_in_test, 'the_allocated_experiment')
    assert_equal('Test', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)

    # Not allocated to the experiment
    exp = Statsig.get_experiment(@user_not_in_exp, 'the_allocated_experiment')
    assert_equal('layerAssignment', exp.rule_id)

    # At this point, we have not opted in to sticky
    assert_empty(persistent_storage_adapter.store)
    assert(!spy_on_save.has_been_called?)

    # Control group with persisted storage enabled
    # (should save to storage, but evaluate as normal until next call)
    exp = Statsig.get_experiment(
      @user_in_control,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_control, 'userID')
      )
    )
    assert_equal('Control', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)

    # Test group with persisted storage enabled
    # (should save to storage, but evaluate as normal until next call)
    exp = Statsig.get_experiment(
      @user_in_test,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_test, 'userID')
      )
    )
    assert_equal('Test', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)

    # Verify that persistent storage has been updated
    assert_equal(2, persistent_storage_adapter.store.size)
    assert_equal(2, spy_on_save.calls.size)

    # Use sticky bucketing with valid persisted values
    # (Should override @user_in_control to the first evaluation of @user_in_control)
    exp = Statsig.get_experiment(
      @user_in_control,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_control, 'userID')
      )
    )
    assert_equal('Control', exp.group_name)
    assert_equal(Statsig::EvaluationReason::PERSISTED, exp.evaluation_details&.reason)

    exp = Statsig.get_experiment(
      @user_in_test,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_test, 'userID')
      )
    )
    assert_equal('Test', exp.group_name)
    assert_equal(Statsig::EvaluationReason::PERSISTED, exp.evaluation_details&.reason)

    # Use sticky bucketing with valid persisted values to assign a user that would otherwise be unallocated
    # (Should override @user_not_in_exp to the first evaluation of @user_in_control)
    exp = Statsig.get_experiment(
      @user_not_in_exp,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_control, 'userID')
      )
    )
    assert_equal('Control', exp.group_name)
    assert_equal(Statsig::EvaluationReason::PERSISTED, exp.evaluation_details&.reason)

    # Use sticky bucketing with valid persisted values for an unallocated user
    # (Should not override since there are no persisted values)
    exp = Statsig.get_experiment(
      @user_not_in_exp,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_not_in_exp, 'userID')
      )
    )
    assert_equal('layerAssignment', exp.rule_id)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)

    # Use sticky bucketing on a different ID type that hasn't been saved to storage
    # (Should not override since there are no persisted values)
    exp = Statsig.get_experiment(
      @user_in_test,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_test, 'stableID')
      )
    )
    assert_equal('Test', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)

    assert_equal(2, persistent_storage_adapter.store.size)
    assert_equal(3, spy_on_save.calls.size)

    # Verify that persisted values are deleted once the experiment is no longer active
    @json_file = File.read("#{__dir__}/data/download_config_specs_sticky_experiments_inactive.json")
    Statsig.shutdown
    Statsig.initialize(
      'secret-key',
      StatsigOptions.new(
        bootstrap_values: @json_file,
        user_persistent_storage: persistent_storage_adapter,
        local_mode: true
      )
    )
    exp = Statsig.get_experiment(
      @user_in_control,
      'another_allocated_experiment_still_active',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_control, 'userID')
      )
    )
    assert_equal('Control', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)
    assert(JSON.parse(persistent_storage_adapter.store["#{@user_in_control.user_id}:userID"]).key?('another_allocated_experiment_still_active'))

    exp = Statsig.get_experiment(
      @user_in_control,
      'the_allocated_experiment',
      Statsig::GetExperimentOptions.new(
        user_persisted_values: Statsig.get_user_persisted_values(@user_in_control, 'userID')
      )
    )
    assert_equal('Control', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)
    assert(!JSON.parse(persistent_storage_adapter.store["#{@user_in_control.user_id}:userID"]).key?('the_allocated_experiment'))

    # Verify that persisted values are deleted once an experiment is evaluated without persisted values (opted-out)
    exp = Statsig.get_experiment(
      @user_in_test,
      'the_allocated_experiment'
    )
    assert_equal('Test', exp.group_name)
    assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)
    assert(!JSON.parse(persistent_storage_adapter.store["#{@user_in_test.user_id}:userID"]).key?('the_allocated_experiment'))
  end

  def test_invalid_storage_adapter
    Statsig.initialize(
      'secret-key',
      StatsigOptions.new(
        bootstrap_values: @json_file,
        user_persistent_storage: InvalidPersistentStorageAdapter.new,
        local_mode: true
      )
    )

    # Verify that exceptions from persistent storage adapter fallback
    assert_nothing_raised do
      exp = Statsig.get_experiment(
        @user_in_control,
        'the_allocated_experiment',
        Statsig::GetExperimentOptions.new(
          user_persisted_values: Statsig.get_user_persisted_values(@user_in_control, 'userID')
        )
      )
      assert_equal('Control', exp.group_name)
      assert_equal(Statsig::EvaluationReason::BOOTSTRAP, exp.evaluation_details&.reason)
    end
  end

  class InvalidPersistentStorageAdapter < Statsig::Interfaces::IUserPersistentStorage
    def load(key)
      raise 'Error in persistent storage adapter load'
    end

    def save(key, data)
      raise 'Error in persistent storage adapter save'
    end
  end

  class DummyPersistentStorageAdapter < Statsig::Interfaces::IUserPersistentStorage
    attr_accessor :store

    def initialize
      @store = {}
    end

    def load(key)
      return nil unless @store&.key?(key)

      @store[key]
    end

    def save(key, data)
      @store[key] = data
    end
  end
end
