# typed: true

require 'config_result'
require 'evaluator'
require 'network'
require 'statsig_errors'
require 'statsig_event'
require 'statsig_logger'
require 'statsig_options'
require 'statsig_user'
require 'spec_store'
require 'dynamic_config'
require 'error_boundary'
require 'layer'
require 'sorbet-runtime'
require 'diagnostics'

class StatsigDriver
  extend T::Sig

  sig { params(secret_key: String, options: T.any(StatsigOptions, NilClass), error_callback: T.any(Method, Proc, NilClass)).void }

  def initialize(secret_key, options = nil, error_callback = nil)
    unless secret_key.start_with?('secret-')
      raise Statsig::ValueError.new('Invalid secret key provided. Provide your project secret key from the Statsig console')
    end

    if !options.nil? && !options.instance_of?(StatsigOptions)
      raise Statsig::ValueError.new('Invalid options provided. Either provide a valid StatsigOptions object or nil')
    end

    @err_boundary = Statsig::ErrorBoundary.new(secret_key)
    @err_boundary.capture(task: lambda {
      @diagnostics = Statsig::Diagnostics.new('initialize')
      tracker = @diagnostics.track('overall')
      @options = options || StatsigOptions.new
      @shutdown = false
      @secret_key = secret_key
      @net = Statsig::Network.new(secret_key, @options)
      @logger = Statsig::StatsigLogger.new(@net, @options, @err_boundary)
      @evaluator = Statsig::Evaluator.new(@net, @options, error_callback, @diagnostics, @err_boundary, @logger)
      tracker.end(success: true)

      @logger.log_diagnostics_event(@diagnostics)
    }, caller: __method__.to_s)
  end

  class CheckGateOptions < T::Struct
    prop :log_exposure, T::Boolean, default: true
  end

  sig { params(user: StatsigUser, gate_name: String, options: CheckGateOptions).returns(T::Boolean) }

  def check_gate(user, gate_name, options = CheckGateOptions.new)
    @err_boundary.capture(task: lambda {
      run_with_diagnostics(task: lambda {
        user = verify_inputs(user, gate_name, "gate_name")

        res = @evaluator.check_gate(user, gate_name)
        if res.nil?
          res = Statsig::ConfigResult.new(gate_name)
        end

        if res == $fetch_from_server
          res = check_gate_fallback(user, gate_name)
          # exposure logged by the server
        else
          if options.log_exposure
            @logger.log_gate_exposure(user, res.name, res.gate_value, res.rule_id, res.secondary_exposures, res.evaluation_details)
          end
        end

        res.gate_value
      }, caller: __method__.to_s)
    }, recover: -> { false }, caller: __method__.to_s)
  end

  sig { params(user: StatsigUser, gate_name: String).void }

  def manually_log_gate_exposure(user, gate_name)
    @err_boundary.capture(task: lambda {
      res = @evaluator.check_gate(user, gate_name)
      context = { 'is_manual_exposure' => true }
      @logger.log_gate_exposure(user, gate_name, res.gate_value, res.rule_id, res.secondary_exposures, res.evaluation_details, context)
    })
  end

  class GetConfigOptions < T::Struct
    prop :log_exposure, T::Boolean, default: true
  end

  sig { params(user: StatsigUser, dynamic_config_name: String, options: GetConfigOptions).returns(DynamicConfig) }

  def get_config(user, dynamic_config_name, options = GetConfigOptions.new)
    @err_boundary.capture(task: lambda {
      run_with_diagnostics(task: lambda {
        user = verify_inputs(user, dynamic_config_name, "dynamic_config_name")
        get_config_impl(user, dynamic_config_name, options)
      }, caller: __method__.to_s)
    }, recover: -> { DynamicConfig.new(dynamic_config_name) }, caller: __method__.to_s)
  end

  class GetExperimentOptions < T::Struct
    prop :log_exposure, T::Boolean, default: true
  end

  sig { params(user: StatsigUser, experiment_name: String, options: GetExperimentOptions).returns(DynamicConfig) }

  def get_experiment(user, experiment_name, options = GetExperimentOptions.new)
    @err_boundary.capture(task: lambda {
      run_with_diagnostics(task: lambda {
        user = verify_inputs(user, experiment_name, "experiment_name")
        get_config_impl(user, experiment_name, options)
      }, caller: __method__.to_s)
    }, recover: -> { DynamicConfig.new(experiment_name) }, caller: __method__.to_s)
  end

  sig { params(user: StatsigUser, config_name: String).void }

  def manually_log_config_exposure(user, config_name)
    @err_boundary.capture(task: lambda {
      res = @evaluator.get_config(user, config_name)
      context = { 'is_manual_exposure' => true }
      @logger.log_config_exposure(user, res.name, res.rule_id, res.secondary_exposures, res.evaluation_details, context)
    }, caller: __method__.to_s)
  end

  class GetLayerOptions < T::Struct
    prop :log_exposure, T::Boolean, default: true
  end

  sig { params(user: StatsigUser, layer_name: String, options: GetLayerOptions).returns(Layer) }

  def get_layer(user, layer_name, options = GetLayerOptions.new)
    @err_boundary.capture(task: lambda {
      run_with_diagnostics(task: lambda {
        user = verify_inputs(user, layer_name, "layer_name")

        res = @evaluator.get_layer(user, layer_name)
        if res.nil?
          res = Statsig::ConfigResult.new(layer_name)
        end

        if res == $fetch_from_server
          if res.config_delegate.empty?
            return Layer.new(layer_name)
          end
          res = get_config_fallback(user, res.config_delegate)
          # exposure logged by the server
        end

        exposure_log_func = options.log_exposure ? lambda { |layer, parameter_name|
          @logger.log_layer_exposure(user, layer, parameter_name, res)
        } : nil
        Layer.new(res.name, res.json_value, res.rule_id, exposure_log_func)
      }, caller: __method__.to_s)
    }, recover: lambda { Layer.new(layer_name) }, caller: __method__.to_s)
  end

  sig { params(user: StatsigUser, layer_name: String, parameter_name: String).void }

  def manually_log_layer_parameter_exposure(user, layer_name, parameter_name)
    @err_boundary.capture(task: lambda {
      res = @evaluator.get_layer(user, layer_name)
      layer = Layer.new(layer_name, res.json_value, res.rule_id)
      context = { 'is_manual_exposure' => true }
      @logger.log_layer_exposure(user, layer, parameter_name, res, context)
    }, caller: __method__.to_s)
  end

  def log_event(user, event_name, value = nil, metadata = nil)
    @err_boundary.capture(task: lambda {
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
    }, caller: __method__.to_s)
  end

  def shutdown
    @err_boundary.capture(task: lambda {
      @shutdown = true
      @logger.shutdown
      @evaluator.shutdown
    }, caller: __method__.to_s)
  end

  def override_gate(gate_name, gate_value)
    @err_boundary.capture(task: lambda {
      @evaluator.override_gate(gate_name, gate_value)
    }, caller: __method__.to_s)
  end

  def override_config(config_name, config_value)
    @err_boundary.capture(task: lambda {
      @evaluator.override_config(config_name, config_value)
    }, caller: __method__.to_s)
  end

  # @param [StatsigUser] user
  # @param [String | nil] client_sdk_key
  # @return [Hash]
  def get_client_initialize_response(user, hash, client_sdk_key)
    @err_boundary.capture(task: lambda {
      validate_user(user)
      normalize_user(user)
      @evaluator.get_client_initialize_response(user, hash, client_sdk_key)
    }, recover: -> { nil }, caller: __method__.to_s)
  end

  def maybe_restart_background_threads
    if @options.local_mode
      return
    end

    @err_boundary.capture(task: lambda {
      @evaluator.maybe_restart_background_threads
      @logger.maybe_restart_background_threads
    }, caller: __method__.to_s)
  end

  private

  def run_with_diagnostics(task:, caller:)
    diagnostics = nil
    if Statsig::Diagnostics::API_CALL_KEYS.include?(caller) && Statsig::Diagnostics.sample(10_000)
      diagnostics = Statsig::Diagnostics.new('api_call')
      tracker = diagnostics.track(caller)
    end
    begin
      res = task.call
      tracker&.end(success: true)
    rescue StandardError => e
      tracker&.end(success: false)
      raise e
    ensure
      @logger.log_diagnostics_event(diagnostics)
    end
    return res
  end

  sig { params(user: StatsigUser, config_name: String, variable_name: String).returns(StatsigUser) }

  def verify_inputs(user, config_name, variable_name)
    validate_user(user)
    if !config_name.is_a?(String) || config_name.empty?
      raise Statsig::ValueError.new("Invalid #{variable_name} provided")
    end

    check_shutdown
    maybe_restart_background_threads
    normalize_user(user)
  end

  def get_config_impl(user, config_name, options)
    res = @evaluator.get_config(user, config_name)
    if res.nil?
      res = Statsig::ConfigResult.new(config_name)
    end

    if res == $fetch_from_server
      res = get_config_fallback(user, config_name)
      # exposure logged by the server
    else
      if options.log_exposure
        @logger.log_config_exposure(user, res.name, res.rule_id, res.secondary_exposures, res.evaluation_details)
      end
    end

    DynamicConfig.new(res.name, res.json_value, res.rule_id, res.group_name, res.id_type)
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
    if !@options&.environment.nil?
      user.statsig_environment = @options.environment
    end
    user
  end

  def check_shutdown
    if @shutdown
      puts 'SDK has been shutdown.  Updates in the Statsig Console will no longer reflect.'
    end
  end

  def check_gate_fallback(user, gate_name)
    network_result = @net.check_gate(user, gate_name)
    if network_result.nil?
      config_result = Statsig::ConfigResult.new(gate_name)
      return config_result
    end

    Statsig::ConfigResult.new(
      network_result['name'],
      network_result['value'],
      {},
      network_result['rule_id'],
    )
  end

  def get_config_fallback(user, dynamic_config_name)
    network_result = @net.get_config(user, dynamic_config_name)
    if network_result.nil?
      config_result = Statsig::ConfigResult.new(dynamic_config_name)
      return config_result
    end

    Statsig::ConfigResult.new(
      network_result['name'],
      false,
      network_result['value'],
      network_result['rule_id'],
    )
  end
end
