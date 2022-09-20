require 'statsig_driver'

module Statsig
  def self.initialize(secret_key, options = nil, error_callback = nil)
    unless @shared_instance.nil?
      puts 'Statsig already initialized.'
      @shared_instance.maybe_restart_background_threads
      return @shared_instance
    end

    @shared_instance = StatsigDriver.new(secret_key, options, error_callback)
  end

  def self.check_gate(user, gate_name)
    ensure_initialized
    @shared_instance&.check_gate(user, gate_name)
  end

  def self.get_config(user, dynamic_config_name)
    ensure_initialized
    @shared_instance&.get_config(user, dynamic_config_name)
  end

  def self.get_experiment(user, experiment_name)
    ensure_initialized
    @shared_instance&.get_experiment(user, experiment_name)
  end

  def self.get_layer(user, layer_name)
    ensure_initialized
    @shared_instance&.get_layer(user, layer_name)
  end

  def self.log_event(user, event_name, value = nil, metadata = nil)
    ensure_initialized
    @shared_instance&.log_event(user, event_name, value, metadata)
  end

  def self.shutdown
    unless @shared_instance.nil?
      @shared_instance.shutdown
    end
    @shared_instance = nil
  end

  def self.override_gate(gate_name, gate_value)
    ensure_initialized
    @shared_instance&.override_gate(gate_name, gate_value)
  end

  def self.override_config(config_name, config_value)
    ensure_initialized
    @shared_instance&.override_config(config_name, config_value)
  end

  def self.get_client_initialize_response(user)
    ensure_initialized
    @shared_instance&.get_client_initialize_response(user)
  end

  def self.get_statsig_metadata
    {
      'sdkType' => 'ruby-server',
      'sdkVersion' => '1.13.0',
    }
  end

  private

  def self.ensure_initialized
    if @shared_instance.nil?
      raise 'Must call initialize first.'
    end
  end
end