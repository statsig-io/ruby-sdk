require 'config_result'
require 'evaluator'
require 'network'
require 'statsig_event'
require 'statsig_logger'
require 'statsig_options'
require 'statsig_user'
require 'spec_store'

class StatsigDriver
  def initialize(secret_key, options = nil)
    super()
    if !secret_key.is_a?(String) || !secret_key.start_with?('secret-')
      raise 'Invalid secret key provided. Provide your project secret key from the Statsig console'
    end
    if !options.nil? && !options.instance_of?(StatsigOptions)
      raise 'Invalid options provided. Either provide a valid StatsigOptions object or nil'
    end

    @options = options || StatsigOptions.new()
    @shutdown = false
    @secret_key = secret_key
    @net = Network.new(secret_key, @options.api_url_base)
    @statsig_metadata = {
      'sdkType' => 'ruby-server',
      'sdkVersion' => Gem::Specification::load('statsig.gemspec')&.version,
    }
    @logger = StatsigLogger.new(@net, @statsig_metadata)

    downloaded_specs = @net.download_config_specs
    unless downloaded_specs.nil?
      @initialized = true
    end

    @store = SpecStore.new(downloaded_specs)
    @evaluator = Evaluator.new(@store)

    @polling_thread = @net.poll_for_changes(-> (config_specs) { @store.process(config_specs) })
  end

  def check_gate(user, gate_name)
    validate_user(user)
    user = normalize_user(user)
    if !gate_name.is_a?(String) || gate_name.empty?
      raise 'Invalid gate_name provided'
    end
    check_shutdown
    unless @initialized
      return false
    end

    res = @evaluator.check_gate(user, gate_name)
    if res.nil?
      res = ConfigResult.new(gate_name)
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
    validate_user(user)
    user = normalize_user(user)
    if !dynamic_config_name.is_a?(String) || dynamic_config_name.empty?
      raise "Invalid dynamic_config_name provided"
    end
    check_shutdown
    unless @initialized
      return DynamicConfig.new(dynamic_config_name)
    end

    res = @evaluator.get_config(user, dynamic_config_name)
    if res.nil?
      res = ConfigResult.new(dynamic_config_name)
    end

    if res == $fetch_from_server
      res = get_config_fallback(user, dynamic_config_name)
      # exposure logged by the server
    else
      @logger.log_config_exposure(user, res.name, res.rule_id, res.secondary_exposures)
    end

    DynamicConfig.new(res.name, res.json_value, res.rule_id)
  end

  def get_experiment(user, experiment_name)
    if !experiment_name.is_a?(String) || experiment_name.empty?
      raise "Invalid experiment_name provided"
    end
    get_config(user, experiment_name)
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
    event.statsig_metadata = @statsig_metadata
    @logger.log_event(event)
  end

  def shutdown
    @shutdown = true
    @logger.flush(true)
    @polling_thread&.exit
  end

  private

  def validate_user(user)
    if user.nil? || !user.instance_of?(StatsigUser) || !user.user_id.is_a?(String)
      raise 'Must provide a valid StatsigUser with a user_id to use the server SDK. See https://docs.statsig.com/messages/serverRequiredUserID/ for more details.'
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
      config_result = ConfigResult.new(gate_name)
      return config_result
    end

    ConfigResult.new(
      network_result['name'],
      network_result['value'],
      {},
      network_result['rule_id'],
    )
  end

  def get_config_fallback(user, dynamic_config_name)
    network_result = @net.get_config(user, dynamic_config_name)
    if network_result.nil?
      config_result = ConfigResult.new(dynamic_config_name)
      return config_result
    end

    ConfigResult.new(
      network_result['name'],
      false,
      network_result['value'],
      network_result['rule_id'],
    )
  end
end