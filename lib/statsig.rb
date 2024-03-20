require 'statsig_driver'

require 'statsig_errors'

module Statsig

  ##
  # Initializes the Statsig SDK.
  #
  # @param secret_key The server SDK key copied from console.statsig.com
  # @param options The StatsigOptions object used to configure the SDK
  # @param error_callback A callback function, called if the initialize network call fails
  def self.initialize(secret_key, options = nil, error_callback = nil)
    unless @shared_instance.nil?
      puts 'Statsig already initialized.'
      @shared_instance.maybe_restart_background_threads
      return @shared_instance
    end

    @shared_instance = StatsigDriver.new(secret_key, options, error_callback)
  end

  class GetGateOptions
    attr_accessor :disable_log_exposure, :skip_evaluation, :disable_evaluation_details

    def initialize(disable_log_exposure: false, skip_evaluation: false, disable_evaluation_details: false)
      @disable_log_exposure = disable_log_exposure
      @skip_evaluation = skip_evaluation
      @disable_evaluation_details = disable_evaluation_details
    end
  end

  ##
  # Gets the gate, evaluated against the given user. An exposure event will automatically be logged for the gate.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] gate_name The name of the gate being checked
  # @param [GetGateOptions] options Additional options for evaluating the gate
  # @return [FeatureGate]
  def self.get_gate(user, gate_name, options)
    ensure_initialized
    @shared_instance&.get_gate(user, gate_name, options)
  end

  class CheckGateOptions
    attr_accessor :disable_log_exposure, :disable_evaluation_details, :ignore_local_overrides

    def initialize(disable_log_exposure: false, disable_evaluation_details: false, ignore_local_overrides: false)
      @disable_log_exposure = disable_log_exposure
      @disable_evaluation_details = disable_evaluation_details
      @ignore_local_overrides = ignore_local_overrides
    end
  end

  ##
  # Gets the boolean result of a gate, evaluated against the given user. An exposure event will automatically be logged for the gate.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] gate_name The name of the gate being checked
  # @param [CheckGateOptions] options Additional options for evaluating the gate
  # @return [Boolean]
  def self.check_gate(user, gate_name, options = nil)
    ensure_initialized
    @shared_instance&.check_gate(user, gate_name, options)
  end

  ##
  # @deprecated - use check_gate(user, gate, options) and disable_exposure_logging in options
  # Gets the boolean result of a gate, evaluated against the given user.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param gate_name The name of the gate being checked
  def self.check_gate_with_exposure_logging_disabled(user, gate_name)
    ensure_initialized
    @shared_instance&.check_gate(user, gate_name, CheckGateOptions.new(disable_log_exposure: true))
  end

  ##
  # Logs an exposure event for the gate
  #
  # @param user A StatsigUser object used for the evaluation
  # @param gate_name The name of the gate being checked
  def self.manually_log_gate_exposure(user, gate_name)
    ensure_initialized
    @shared_instance&.manually_log_gate_exposure(user, gate_name)
  end

  class GetConfigOptions
    attr_accessor :disable_log_exposure, :disable_evaluation_details, :ignore_local_overrides

    def initialize(disable_log_exposure: false, disable_evaluation_details: false, ignore_local_overrides: false)
      @disable_log_exposure = disable_log_exposure
      @disable_evaluation_details = disable_evaluation_details
      @ignore_local_overrides = ignore_local_overrides
    end
  end

  ##
  # Get the values of a dynamic config, evaluated against the given user. An exposure event will automatically be logged for the dynamic config.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] dynamic_config_name The name of the dynamic config
  # @param [GetConfigOptions] options Additional options for evaluating the config
  # @return [DynamicConfig]
  def self.get_config(user, dynamic_config_name, options = nil)
    ensure_initialized
    @shared_instance&.get_config(user, dynamic_config_name, options)
  end

  ##
  # @deprecated - use get_config(user, config, options) and disable_exposure_logging in options
  # Get the values of a dynamic config, evaluated against the given user.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] dynamic_config_name The name of the dynamic config
  # @return [DynamicConfig]
  def self.get_config_with_exposure_logging_disabled(user, dynamic_config_name)
    ensure_initialized
    @shared_instance&.get_config(user, dynamic_config_name, GetConfigOptions.new(disable_log_exposure: true))
  end

  ##
  # Logs an exposure event for the dynamic config
  #
  # @param user A StatsigUser object used for the evaluation
  # @param dynamic_config_name The name of the dynamic config
  def self.manually_log_config_exposure(user, dynamic_config)
    ensure_initialized
    @shared_instance&.manually_log_config_exposure(user, dynamic_config)
  end

  class GetExperimentOptions
    attr_accessor :disable_log_exposure, :user_persisted_values, :disable_evaluation_details, :ignore_local_overrides

    def initialize(disable_log_exposure: false, user_persisted_values: nil, disable_evaluation_details: false, ignore_local_overrides: false)
      @disable_log_exposure = disable_log_exposure
      @user_persisted_values = user_persisted_values
      @disable_evaluation_details = disable_evaluation_details
      @ignore_local_overrides = ignore_local_overrides
    end
  end

  ##
  # Get the values of an experiment, evaluated against the given user. An exposure event will automatically be logged for the experiment.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] experiment_name The name of the experiment
  # @param [GetExperimentOptions] options Additional options for evaluating the experiment
  def self.get_experiment(user, experiment_name, options = nil)
    ensure_initialized
    @shared_instance&.get_experiment(user, experiment_name, options)
  end

  ##
  # @deprecated - use get_experiment(user, experiment, options) and disable_exposure_logging in options
  # Get the values of an experiment, evaluated against the given user.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] experiment_name The name of the experiment
  def self.get_experiment_with_exposure_logging_disabled(user, experiment_name)
    ensure_initialized
    @shared_instance&.get_experiment(user, experiment_name, GetExperimentOptions.new(disable_log_exposure: true))
  end

  ##
  # Logs an exposure event for the experiment
  #
  # @param user A StatsigUser object used for the evaluation
  # @param experiment_name The name of the experiment
  def self.manually_log_experiment_exposure(user, experiment_name)
    ensure_initialized
    @shared_instance&.manually_log_config_exposure(user, experiment_name)
  end

  def self.get_user_persisted_values(user, id_type)
    ensure_initialized
    @shared_instance&.get_user_persisted_values(user, id_type)
  end

  class GetLayerOptions
    attr_accessor :disable_log_exposure, :disable_evaluation_details

    def initialize(disable_log_exposure: false, disable_evaluation_details: false)
      @disable_log_exposure = disable_log_exposure
      @disable_evaluation_details = disable_evaluation_details
    end
  end

  ##
  # Get the values of a layer, evaluated against the given user.
  # Exposure events will be fired when get or get_typed is called on the resulting Layer class.
  #
  # @param [StatsigUser] user A StatsigUser object used for the evaluation
  # @param [String] layer_name The name of the layer
  # @param [GetLayerOptions] options Configuration of how this method call should behave
  def self.get_layer(user, layer_name, options = nil)
    ensure_initialized
    @shared_instance&.get_layer(user, layer_name, options)
  end

  ##
  # @deprecated - use get_layer(user, gate, options) and disable_exposure_logging in options
  # Get the values of a layer, evaluated against the given user.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param layer_name The name of the layer
  def self.get_layer_with_exposure_logging_disabled(user, layer_name)
    ensure_initialized
    @shared_instance&.get_layer(user, layer_name, GetLayerOptions.new(disable_log_exposure: true))
  end

  ##
  # Logs an exposure event for the parameter in the given layer
  #
  # @param user A StatsigUser object used for the evaluation
  # @param layer_name The name of the layer
  # @param parameter_name The name of the parameter in the layer
  def self.manually_log_layer_parameter_exposure(user, layer_name, parameter_name)
    ensure_initialized
    @shared_instance&.manually_log_layer_parameter_exposure(user, layer_name, parameter_name)
  end

  ##
  # Logs an event to Statsig with the provided values.
  #
  # @param user A StatsigUser object to be included in the log
  # @param event_name The name given to the event
  # @param value A top level value for the event
  # @param metadata Any extra values to be logged
  def self.log_event(user, event_name, value = nil, metadata = nil)
    ensure_initialized
    @shared_instance&.log_event(user, event_name, value, metadata)
  end

  def self.sync_rulesets
    ensure_initialized
    @shared_instance&.manually_sync_rulesets
  end

  def self.sync_idlists
    ensure_initialized
    @shared_instance&.manually_sync_idlists
  end

  ##
  # Returns a list of all gate names
  #
  def self.list_gates
    ensure_initialized
    @shared_instance&.list_gates
  end

  ##
  # Returns a list of all config names
  #
  def self.list_configs
    ensure_initialized
    @shared_instance&.list_configs
  end

  ##
  # Returns a list of all experiment names
  #
  def self.list_experiments
    ensure_initialized
    @shared_instance&.list_experiments
  end

  ##
  # Returns a list of all autotune names
  #
  def self.list_autotunes
    ensure_initialized
    @shared_instance&.list_autotunes
  end

  ##
  # Returns a list of all layer names
  #
  def self.list_layers
    ensure_initialized
    @shared_instance&.list_layers
  end

  ##
  # Stops all Statsig activity and flushes any pending events.
  def self.shutdown
    if defined? @shared_instance and !@shared_instance.nil?
      @shared_instance.shutdown
    end
    @shared_instance = nil
  end

  ##
  # Sets a value to be returned for the given gate instead of the actual evaluated value.
  #
  # @param gate_name The name of the gate to be overridden
  # @param gate_value The value that will be returned
  def self.override_gate(gate_name, gate_value)
    ensure_initialized
    @shared_instance&.override_gate(gate_name, gate_value)
  end

  def self.remove_gate_override(gate_name)
    ensure_initialized
    @shared_instance&.remove_gate_override(gate_name)
  end

  def self.clear_gate_overrides
    ensure_initialized
    @shared_instance&.clear_gate_overrides
  end

  ##
  # Sets a value to be returned for the given dynamic config/experiment instead of the actual evaluated value.
  #
  # @param config_name The name of the dynamic config or experiment to be overridden
  # @param config_value The value that will be returned
  def self.override_config(config_name, config_value)
    ensure_initialized
    @shared_instance&.override_config(config_name, config_value)
  end

  def self.remove_config_override(config_name)
    ensure_initialized
    @shared_instance&.remove_config_override(config_name)
  end

  def self.clear_config_overrides
    ensure_initialized
    @shared_instance&.clear_config_overrides
  end

  ##
  # @param [HashTable] debug information log with exposure events
  def self.set_debug_info(debug_info)
    ensure_initialized
    @shared_instance&.set_debug_info(debug_info)
  end

  ##
  # Gets all evaluated values for the given user.
  # These values can then be given to a Statsig Client SDK via bootstrapping.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param hash The type of hashing algorithm to use ('sha256', 'djb2', 'none')
  # @param client_sdk_key A optional client sdk key to be used for the evaluation
  # @param include_local_overrides Option to include local overrides
  #
  # @note See Ruby Documentation: https://docs.statsig.com/server/rubySDK)
  def self.get_client_initialize_response(
    user,
    hash: 'sha256',
    client_sdk_key: nil,
    include_local_overrides: false
  )
    ensure_initialized
    @shared_instance&.get_client_initialize_response(user, hash, client_sdk_key, include_local_overrides)
  end

  ##
  # Internal Statsig metadata for this SDK
  def self.get_statsig_metadata
    {
      'sdkType' => 'ruby-server',
      'sdkVersion' => '1.33.3.pre.beta.1',
      'languageVersion' => RUBY_VERSION
    }
  end

  private

  def self.ensure_initialized
    if not defined? @shared_instance or @shared_instance.nil?
      raise Statsig::UninitializedError.new
    end
  end

end
