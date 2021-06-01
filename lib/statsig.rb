require 'statsig_driver'

module Statsig
  def self.initialize(secret_key)
    unless @shared_instance.nil?
      puts 'Statsig already initialized.'
      return @shared_instance
    end

    @shared_instance = StatsigDriver.new(secret_key)
  end

  def self.check_gate(user, gate_name)
    self.ensure_initialized
    @shared_instance.check_gate(user, gate_name)
  end

  def self.get_config(user, dynamic_config_name)
    self.ensure_initialized
    @shared_instance.get_config(user, dynamic_config_name)
  end

  def self.log_event(user, event_name, value, metadata)
    self.ensure_initialized
    @shared_instance.log_event(user, event_name, value, metadata)
  end

  def self.shutdown
    unless @shared_instance.nil?
      @shared_instance.shutdown
    end
    @shared_instance = nil
  end

  private

  def self.ensure_initialized
    if @shared_instance.nil?
      raise 'Must call initialize first.'
    end
  end
end