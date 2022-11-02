# typed: true

require 'statsig_driver'
require 'sorbet-runtime'
require 'statsig_errors'

module Statsig
  extend T::Sig


  sig { params(secret_key: String, options: T.any(StatsigOptions, NilClass), error_callback: T.any(Method, Proc, NilClass)).void }
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

  sig { params(user: StatsigUser, gate_name: String).returns(T::Boolean) }
  ##
  # Gets the boolean result of a gate, evaluated against the given user. An exposure event will automatically be logged for the gate.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param gate_name The name of the gate being checked
  def self.check_gate(user, gate_name)
    ensure_initialized
    @shared_instance&.check_gate(user, gate_name)
  end

  sig { params(user: StatsigUser, dynamic_config_name: String).returns(DynamicConfig) }
  ##
  # Get the values of a dynamic config, evaluated against the given user. An exposure event will automatically be logged for the dynamic config.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param dynamic_config_name The name of the dynamic config
  def self.get_config(user, dynamic_config_name)
    ensure_initialized
    @shared_instance&.get_config(user, dynamic_config_name)
  end

  sig { params(user: StatsigUser, experiment_name: String).returns(DynamicConfig) }
  ##
  # Get the values of an experiment, evaluated against the given user. An exposure event will automatically be logged for the experiment.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param experiment_name The name of the experiment
  def self.get_experiment(user, experiment_name)
    ensure_initialized
    @shared_instance&.get_experiment(user, experiment_name)
  end

  sig { params(user: StatsigUser, layer_name: String).returns(Layer) }
  ##
  # Get the values of a layer, evaluated against the given user.
  # Exposure events will be fired when get or get_typed is called on the resulting Layer class.
  #
  # @param user A StatsigUser object used for the evaluation
  # @param layer_name The name of the layer
  def self.get_layer(user, layer_name)
    ensure_initialized
    @shared_instance&.get_layer(user, layer_name)
  end

  sig { params(user: StatsigUser,
               event_name: String,
               value: T.any(String, Integer, Float, NilClass),
               metadata: T.any(T::Hash[String, T.untyped], NilClass)).void }
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

  sig { void }
  ##
  # Stops all Statsig activity and flushes any pending events.
  def self.shutdown
    unless @shared_instance.nil?
      @shared_instance.shutdown
    end
    @shared_instance = nil
  end

  sig { params(gate_name: String, gate_value: T::Boolean).void }
  ##
  # Sets a value to be returned for the given gate instead of the actual evaluated value.
  #
  # @param gate_name The name of the gate to be overridden
  # @param gate_value The value that will be returned
  def self.override_gate(gate_name, gate_value)
    ensure_initialized
    @shared_instance&.override_gate(gate_name, gate_value)
  end

  sig { params(config_name: String, config_value: Hash).void }
  ##
  # Sets a value to be returned for the given dynamic config/experiment instead of the actual evaluated value.
  #
  # @param config_name The name of the dynamic config or experiment to be overridden
  # @param config_value The value that will be returned
  def self.override_config(config_name, config_value)
    ensure_initialized
    @shared_instance&.override_config(config_name, config_value)
  end

  sig { params(user: StatsigUser).returns(T.any(T::Hash[String, T.untyped], NilClass)) }
  ##
  # Gets all evaluated values for the given user.
  # These values can then be given to a Statsig Client SDK via bootstrapping.
  #
  # @param user A StatsigUser object used for the evaluation
  #
  # @note See Ruby Documentation: https://docs.statsig.com/server/rubySDK)
  def self.get_client_initialize_response(user)
    ensure_initialized
    @shared_instance&.get_client_initialize_response(user)
  end

  sig { returns(T::Hash[String, String]) }
  ##
  # Internal Statsig metadata for this SDK
  def self.get_statsig_metadata
    {
      'sdkType' => 'ruby-server',
      'sdkVersion' => '1.17.0',
    }
  end

  private

  def self.ensure_initialized
    if @shared_instance.nil?
      raise Statsig::UninitializedError.new
    end
  end

  T::Configuration.call_validation_error_handler = lambda do |signature, opts|
    puts opts[:pretty_message]
  end

  T::Configuration.inline_type_error_handler = lambda do |error, opts|
    puts error.message
  end

  T::Configuration.sig_builder_error_handler = lambda do |error, location|
    puts error.message
  end

  T::Configuration.sig_validation_error_handler = lambda do |error, opts|
    puts error.message
  end

end