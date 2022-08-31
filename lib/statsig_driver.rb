require 'config_result'
require 'evaluator'
require 'network'
require 'statsig_event'
require 'statsig_logger'
require 'statsig_options'
require 'statsig_user'
require 'spec_store'
require 'dynamic_config'
require 'layer'

class StatsigDriver
  def initialize(secret_key, options = nil, error_callback = nil)
    super()
    if !secret_key.is_a?(String) || !secret_key.start_with?('secret-')
      raise 'Invalid secret key provided. Provide your project secret key from the Statsig console'
    end
    if !options.nil? && !options.instance_of?(StatsigOptions)
      raise 'Invalid options provided. Either provide a valid StatsigOptions object or nil'
    end

    @options = options || StatsigOptions.new
    @shutdown = false
    @secret_key = secret_key
    @net = Statsig::Network.new(secret_key, @options.api_url_base, @options.local_mode)
    @logger = Statsig::StatsigLogger.new(@net, @options)
    @evaluator = Statsig::Evaluator.new(@net, @options, error_callback)
  end

  def check_gate(user, gate_name)
    user = verify_inputs(user, gate_name, "gate_name")

    res = @evaluator.check_gate(user, gate_name)
    if res.nil?
      res = Statsig::ConfigResult.new(gate_name)
    end

    if res == $fetch_from_server
      res = check_gate_fallback(user, gate_name)
      # exposure logged by the server
    else
      @logger.log_gate_exposure(user, res.name, res.gate_value, res.rule_id, res.secondary_exposures)
    end

    res.gate_value
  end

  def get_config(user, dynamic_config_name)
    user = verify_inputs(user, dynamic_config_name, "dynamic_config_name")
    get_config_impl(user, dynamic_config_name)
  end

  def get_experiment(user, experiment_name)
    user = verify_inputs(user, experiment_name, "experiment_name")
    get_config_impl(user, experiment_name)
  end

  def get_layer(user, layer_name)
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

    Layer.new(res.name, res.json_value, res.rule_id, lambda { |layer, parameter_name|
      @logger.log_layer_exposure(user, layer, parameter_name, res)
    })
  end

  def log_event(user, event_name, value = nil, metadata = nil)
    if !user.nil? && !user.instance_of?(StatsigUser)
      raise 'Must provide a valid StatsigUser or nil'
    end
    check_shutdown

    user = normalize_user(user)

    event = StatsigEvent.new(event_name)
    event.user = user
    event.value = value
    event.metadata = metadata
    event.statsig_metadata = Statsig.get_statsig_metadata
    @logger.log_event(event)
  end

  def shutdown
    @shutdown = true
    @logger.flush(true)
    @evaluator.shutdown
  end

  def override_gate(gate_name, gate_value)
    @evaluator.override_gate(gate_name, gate_value)
  end

  def override_config(config_name, config_value)
    @evaluator.override_config(config_name, config_value)
  end

  # @param [StatsigUser] user
  # @return [Hash]
  def get_client_initialize_response(user)
    normalize_user(user)
    @evaluator.get_client_initialize_response(user)
  end

  private

  def verify_inputs(user, config_name, variable_name)
    validate_user(user)
    if !config_name.is_a?(String) || config_name.empty?
      raise "Invalid #{variable_name} provided"
    end

    check_shutdown
    normalize_user(user)
  end

  def get_config_impl(user, config_name)
    res = @evaluator.get_config(user, config_name)
    if res.nil?
      res = Statsig::ConfigResult.new(config_name)
    end

    if res == $fetch_from_server
      res = get_config_fallback(user, config_name)
      # exposure logged by the server
    else
      @logger.log_config_exposure(user, res.name, res.rule_id, res.secondary_exposures)
    end

    DynamicConfig.new(res.name, res.json_value, res.rule_id)
  end

  def validate_user(user)
    if user.nil? ||
      !user.instance_of?(StatsigUser) ||
      (
        # user_id is nil and custom_ids is not a hash with entries
        !user.user_id.is_a?(String) &&
          (!user.custom_ids.is_a?(Hash) || user.custom_ids.size == 0)
      )
      raise 'Must provide a valid StatsigUser with a user_id or at least a custom ID. See https://docs.statsig.com/messages/serverRequiredUserID/ for more details.'
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