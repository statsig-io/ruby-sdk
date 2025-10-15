require_relative 'api_config'
require_relative 'config_result'
require_relative 'diagnostics'
require_relative 'dynamic_config'
require_relative 'error_boundary'
require_relative 'evaluator'
require_relative 'feature_gate'
require_relative 'layer'
require_relative 'memo'
require_relative 'network'
require_relative 'sdk_configs'
require_relative 'spec_store'
require_relative 'statsig_errors'
require_relative 'statsig_event'
require_relative 'statsig_logger'
require_relative 'statsig_options'
require_relative 'statsig_user'

class StatsigDriver

  def initialize(secret_key, options = nil, error_callback = nil)
    unless secret_key.start_with?('secret-')
      raise Statsig::ValueError.new('Invalid secret key provided. Provide your project secret key from the Statsig console')
    end

    if !options.nil? && !options.instance_of?(StatsigOptions)
      raise Statsig::ValueError.new('Invalid options provided. Either provide a valid StatsigOptions object or nil')
    end

    @err_boundary = Statsig::ErrorBoundary.new(secret_key, !options.nil? && options.local_mode)
    @err_boundary.capture(caller: __method__) do
      @diagnostics = Statsig::Diagnostics.new
      @sdk_configs = Statsig::SDKConfigs.new
      tracker = @diagnostics.track('initialize', 'overall')
      @options = options || StatsigOptions.new
      @shutdown = false
      @secret_key = secret_key
      @net = Statsig::Network.new(secret_key, @options)
      @logger = Statsig::StatsigLogger.new(@net, @options, @err_boundary, @sdk_configs)
      @persistent_storage_utils = Statsig::UserPersistentStorageUtils.new(@options)
      @store = Statsig::SpecStore.new(@net, @options, error_callback, @diagnostics, @err_boundary, @logger, secret_key, @sdk_configs)
      @evaluator = Statsig::Evaluator.new(@store, @options, @persistent_storage_utils)
      tracker.end(success: true)

      @logger.log_diagnostics_event(@diagnostics, 'initialize')
    end
  end

  def get_initialization_details
    @store.get_initialization_details
  end

  def get_gate_impl(
    user,
    gate_name,
    disable_log_exposure: false,
    skip_evaluation: false,
    disable_evaluation_details: false,
    ignore_local_overrides: false
  )
    if skip_evaluation
      gate = @store.get_gate(gate_name)
      return FeatureGate.new(gate_name) if gate.nil?
      return FeatureGate.new(gate_name, target_app_ids: gate[:targetAppIDs])
    end

    user = verify_inputs(user, gate_name, 'gate_name')

    Statsig::Memo.for(user.get_memo, :get_gate_impl, gate_name, disable_evaluation_memoization: @options.disable_evaluation_memoization) do
      res = Statsig::ConfigResult.new(
        name: gate_name,
        disable_exposures: disable_log_exposure,
        disable_evaluation_details: disable_evaluation_details
      )
      @evaluator.check_gate(user, gate_name, res, ignore_local_overrides: ignore_local_overrides)

      unless disable_log_exposure
        @logger.log_gate_exposure(user, res)
      end

      FeatureGate.from_config_result(res)
    end
  end


  def get_gate(user, gate_name, options = nil)
    @err_boundary.capture(caller: __method__, recover: -> {false}) do
      run_with_diagnostics(caller: :get_gate) do
        get_gate_impl(user, gate_name,
                      disable_log_exposure: options&.disable_log_exposure == true,
                      skip_evaluation: options&.skip_evaluation == true,
                      disable_evaluation_details: options&.disable_evaluation_details == true
        )
      end
    end
  end

  def check_gate(user, gate_name, options = nil)
    @err_boundary.capture(caller: __method__, recover: -> {false}) do
      run_with_diagnostics(caller: :check_gate) do
        get_gate_impl(
          user,
          gate_name,
          disable_log_exposure: options&.disable_log_exposure == true,
          disable_evaluation_details: options&.disable_evaluation_details == true,
          ignore_local_overrides: options&.ignore_local_overrides == true
        ).value
      end
    end
  end

  def manually_log_gate_exposure(user, gate_name)
    @err_boundary.capture(caller: __method__) do
      res = Statsig::ConfigResult.new(name: gate_name)
      @evaluator.check_gate(user, gate_name, res)
      context = { :is_manual_exposure => true }
      @logger.log_gate_exposure(user, res, context)
    end
  end

  def get_fields_used_for_gate(gate_name)
    @err_boundary.capture(caller: __method__, recover: -> { [] }) do
        gate = @store.get_gate(gate_name)
        return [] if gate.nil?

        gate[:fieldsUsed] || []
    end
  end

  def get_config(user, dynamic_config_name, options = nil)
    @err_boundary.capture(caller: __method__, recover: -> { DynamicConfig.new(dynamic_config_name) }) do
      run_with_diagnostics(caller: :get_config) do
        user = verify_inputs(user, dynamic_config_name, "dynamic_config_name")
        get_config_impl(
          user,
          dynamic_config_name,
          options&.disable_log_exposure == true,
          disable_evaluation_details: options&.disable_evaluation_details == true,
          ignore_local_overrides: options&.ignore_local_overrides == true
        )
      end
    end
  end

  def get_fields_used_for_config(config_name)
    @err_boundary.capture(caller: __method__, recover: -> { [] }) do
        config = @store.get_config(config_name)
        return [] if config.nil?

        config[:fieldsUsed] || []
    end
  end

  def get_experiment(user, experiment_name, options = nil)
    @err_boundary.capture(caller: __method__, recover: -> { DynamicConfig.new(experiment_name) }) do
      run_with_diagnostics(caller: :get_experiment) do
        user = verify_inputs(user, experiment_name, "experiment_name")
        get_config_impl(
          user,
          experiment_name,
          options&.disable_log_exposure == true,
          user_persisted_values: options&.user_persisted_values,
          disable_evaluation_details: options&.disable_evaluation_details == true,
          ignore_local_overrides: options&.ignore_local_overrides == true
        )
      end
    end
  end

  def manually_log_config_exposure(user, config_name)
    @err_boundary.capture(caller: __method__) do
      res = Statsig::ConfigResult.new(name: config_name)
      @evaluator.get_config(user, config_name, res)

      context = { :is_manual_exposure => true }
      @logger.log_config_exposure(user, res, context)
    end
  end

  def get_user_persisted_values(user, id_type)
    @err_boundary.capture(caller: __method__,) do
      persisted_values = @persistent_storage_utils.get_user_persisted_values(user, id_type)
      return {} if persisted_values.nil?

      persisted_values
    end
  end

  def get_layer(user, layer_name, options = nil)
    @err_boundary.capture(caller: __method__, recover: -> { Layer.new(layer_name) }) do
      run_with_diagnostics(caller: :get_layer) do
        user = verify_inputs(user, layer_name, "layer_name")
        Statsig::Memo.for(user.get_memo, :get_layer, layer_name, disable_evaluation_memoization: @options.disable_evaluation_memoization) do
          exposures_disabled = options&.disable_log_exposure == true
          res = Statsig::ConfigResult.new(
            name: layer_name,
            disable_exposures: exposures_disabled,
            disable_evaluation_details: options&.disable_evaluation_details == true
          )
          @evaluator.get_layer(user, layer_name, res)

          exposure_log_func = !exposures_disabled ? lambda { |layer, parameter_name|
            @logger.log_layer_exposure(user, layer, parameter_name, res)
          } : nil

          Layer.new(res.name, res.json_value, res.rule_id, res.group_name, res.config_delegate, exposure_log_func)
        end
      end
    end
  end

  def manually_log_layer_parameter_exposure(user, layer_name, parameter_name)
    @err_boundary.capture(caller: __method__) do
      res = Statsig::ConfigResult.new(name: layer_name)
      @evaluator.get_layer(user, layer_name, res)

      layer = Layer.new(layer_name, res.json_value, res.rule_id, res.group_name, res.config_delegate)
      context = { :is_manual_exposure => true }
      @logger.log_layer_exposure(user, layer, parameter_name, res, context)
    end
  end

  def get_fields_used_for_layer(layer_name)
    @err_boundary.capture(caller: __method__, recover: -> { [] }) do
        layer = @store.get_layer(layer_name)
        return [] if layer.nil?

        layer[:fieldsUsed] || []
    end
  end

  def log_event(user, event_name, value = nil, metadata = nil)
    @err_boundary.capture(caller: __method__) do
      if !user.nil? && !user.instance_of?(StatsigUser)
        raise Statsig::ValueError.new('Must provide a valid StatsigUser or nil')
      end
      check_shutdown

      user = normalize_user(user)

      event = StatsigEvent.new(event_name)
      event.user = user
      event.value = value
      event.metadata = metadata
      @logger.log_event(event)
    end
  end

  def manually_sync_rulesets
    @err_boundary.capture(caller: __method__) do
      @evaluator.spec_store.sync_config_specs
    end
  end

  def manually_sync_idlists
    @err_boundary.capture(caller: __method__) do
      @evaluator.spec_store.sync_id_lists
    end
  end

  def list_gates
    @err_boundary.capture(caller: __method__) do
      @evaluator.list_gates
    end
  end

  def list_configs
    @err_boundary.capture(caller: __method__) do
      @evaluator.list_configs
    end
  end

  def list_experiments
    @err_boundary.capture(caller: __method__) do
      @evaluator.list_experiments
    end
  end

  def list_autotunes
    @err_boundary.capture(caller: __method__) do
      @evaluator.list_autotunes
    end
  end

  def list_layers
    @err_boundary.capture(caller: __method__) do
      @evaluator.list_layers
    end
  end

  def shutdown
    @err_boundary.capture(caller: __method__) do
      @shutdown = true
      @logger.shutdown
      @evaluator.shutdown
    end
  end

  def override_gate(gate_name, gate_value)
    @err_boundary.capture(caller: __method__) do
      @evaluator.override_gate(gate_name, gate_value)
    end
  end

  def remove_gate_override(gate_name)
    @err_boundary.capture(caller: __method__) do
      @evaluator.remove_gate_override(gate_name)
    end
  end

  def clear_gate_overrides
    @err_boundary.capture(caller: __method__) do
      @evaluator.clear_gate_overrides
    end
  end

  def override_config(config_name, config_value)
    @err_boundary.capture(caller: __method__) do
      @evaluator.override_config(config_name, config_value)
    end
  end

  def remove_config_override(config_name)
    @err_boundary.capture(caller: __method__) do
      @evaluator.remove_config_override(config_name)
    end
  end

  def clear_config_overrides
    @err_boundary.capture(caller: __method__) do
      @evaluator.clear_config_overrides
    end
  end

  def clear_experiment_overrides
    @err_boundary.capture(caller: __method__) do
      @evaluator.clear_experiment_overrides
    end
  end

  def set_debug_info(debug_info)
    @err_boundary.capture(caller: __method__) do
      @logger.set_debug_info(debug_info)
    end
  end

  # @param [StatsigUser] user
  # @param [String | nil] client_sdk_key
  # @param [Boolean] include_local_overrides
  # @return [Hash]
  def get_client_initialize_response(user, hash, client_sdk_key, include_local_overrides)
    @err_boundary.capture(caller: __method__, recover: -> { nil }) do
      validate_user(user)
      normalize_user(user)
      response = @evaluator.get_client_initialize_response(user, hash, client_sdk_key, include_local_overrides)
      if response.nil?
        @err_boundary.log_exception(Statsig::ValueError.new('Failed to get client initialize response'), tag: 'getClientInitializeResponse', extra: {hash: hash, clientKey: client_sdk_key})
      end
      response
    end
  end

  def maybe_restart_background_threads
    if @options.local_mode
      return
    end

    @err_boundary.capture(caller: __method__) do
      @evaluator.maybe_restart_background_threads
      @logger.maybe_restart_background_threads
    end
  end

  def override_experiment_by_group_name(experiment_name, group_name)
    @evaluator.override_experiment_by_group_name(experiment_name, group_name)
  end

  private

  def run_with_diagnostics(caller:)
    if !Statsig::Diagnostics::API_CALL_KEYS[caller] || !Statsig::Diagnostics.sample(1)
      return yield
    end

    diagnostics = Statsig::Diagnostics.new()
    tracker = diagnostics.track('api_call', caller.to_s)

    begin
      res = yield
      tracker&.end(success: true)
    rescue StandardError => e
      tracker&.end(success: false)
      raise e
    ensure
      @logger.log_diagnostics_event(diagnostics, 'api_call')
    end
    return res
  end

  def verify_inputs(user, config_name, variable_name)
    validate_user(user)
    user = Statsig::Memo.for(user.get_memo(), :verify_inputs, 0, disable_evaluation_memoization: @options.disable_evaluation_memoization) do
      user = normalize_user(user)
      check_shutdown
      maybe_restart_background_threads
      user
    end

    if !config_name.is_a?(String) || config_name.empty?
      raise Statsig::ValueError.new("Invalid #{variable_name} provided")
    end

    user
  end

  def get_config_impl(user, config_name, disable_log_exposure, user_persisted_values: nil, disable_evaluation_details: false, ignore_local_overrides: false)
    Statsig::Memo.for(user.get_memo, :get_config_impl, config_name, disable_evaluation_memoization: @options.disable_evaluation_memoization) do
      res = Statsig::ConfigResult.new(
        name: config_name,
        disable_exposures: disable_log_exposure,
        disable_evaluation_details: disable_evaluation_details
      )
      @evaluator.get_config(user, config_name, res, user_persisted_values: user_persisted_values, ignore_local_overrides: ignore_local_overrides)

      unless disable_log_exposure
        @logger.log_config_exposure(user, res)
      end

      DynamicConfig.new(res.name, res.json_value, res.rule_id, res.group_name, res.id_type, res.evaluation_details)
    end
  end

  def validate_user(user)
    if user.nil? ||
      !user.instance_of?(StatsigUser) ||
      (
        # user_id is nil and custom_ids is not a hash with entries
        !user.user_id.is_a?(String) &&
          (!user.custom_ids.is_a?(Hash) || user.custom_ids.size == 0)
      )
      raise Statsig::ValueError.new('Must provide a valid StatsigUser with a user_id or at least a custom ID. See https://docs.statsig.com/messages/serverRequiredUserID/ for more details.')
    end
  end

  def normalize_user(user)
    if user.statsig_environment.nil? && !@options&.environment.nil?
      user.statsig_environment = @options.environment
    end
    user
  end

  def check_shutdown
    if @shutdown
      puts 'SDK has been shutdown.  Updates in the Statsig Console will no longer reflect.'
    end
  end
end
