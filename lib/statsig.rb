require 'concurrent'
require 'config_result'
require 'evaluator'
require 'network'
require 'statsig_event'
require 'statsig_logger'
require 'statsig_user'
require 'spec_store'

class Statsig
    include Concurrent::Async

    def initialize(secret_key)
        super()
        if !secret_key.is_a?(String) || !secret_key.start_with?('secret-')
          raise 'Invalid secret key provided. Provide your project secret key from the Statsig console'
        end
        @shutdown = false
        @secret_key = secret_key
        @net = Network.new(secret_key, 'https://api.statsig.com/v1/')
        @statsig_metadata = {
          'sdkType' => 'ruby-server',
          'sdkVersion' => Gem::Specification::load('statsig.gemspec'),
        }
        @logger = StatsigLogger.new(@net, @statsig_metadata)

        downloaded_specs = @net.download_config_specs()
        if !downloaded_specs.nil?
          @initialized = true
        end

        @store = SpecStore.new(downloaded_specs)
        @evaluator = Evaluator.new(@store)

        @polling_thread = @net.poll_for_changes(-> (config_specs) { @store.process(config_specs) })
    end
  
    def check_gate(user, gate_name)
      if !user.nil? && !user.instance_of?(StatsigUser)
        raise 'Must provide a valid StatsigUser'
      end
      if !gate_name.is_a?(String) || gate_name.empty?
        raise 'Invalid gate_name provided'
      end
      check_shutdown()
      if !@initialized
        return false
      end

      res = @evaluator.check_gate(user, gate_name)
      if res.nil?
        @logger.logConfigExposure(user, gate_name, nil)
        return false
      end

      if res == $fetch_from_server
        res = check_gate_fallback(user, gate_name)
      end

      @logger.logGateExposure(user, res.name, res.gate_value, res.rule_id)
      return res.gate_value
    end

    def get_config(user, dynamic_config_name)
      if !user.nil? && !user.instance_of?(StatsigUser)
        raise 'Must provide a valid StatsigUser or nil'
      end
      if !dynamic_config_name.is_a?(String) || dynamic_config_name.empty?
        raise "Invalid dynamic_config_name provided"
      end
      check_shutdown()
      if !@initialized
        return DynamicConfig.new(dynamic_config_name)
      end

      res = @evaluator.get_config(user, dynamic_config_name)
      if res.nil?
        @logger.logConfigExposure(user, dynamic_config_name, nil)
        return DynamicConfig.new()
      end

      if res == $fetch_from_server
        res = get_config_fallback(user, dynamic_config_name)
      end

      result_config = DynamicConfig.new(res.name)
      result_config.value = res.json_value
      result_config.rule_id = res.rule_id
      @logger.logConfigExposure(user, dynamic_config_name, result_config.rule_id)
      return result_config
    end

    def log_event(user, event_name, value = nil, metadata = nil)
      if !user.nil? && !user.instance_of?(StatsigUser)
        raise 'Must provide a valid StatsigUser or nil'
      end
      check_shutdown()

      event = StatsigEvent.new(event_name)
      event.user = user&.serialize()
      event.value = value
      event.metadata = metadata
      event.statsig_metadata = @statsig_metadata
      @logger.log_event(event)
    end

    def shutdown
      @shutdown = true
      @logger.flush
      @polling_thread&.exit
    end

    private

    def check_shutdown
      if @shutdown
        raise 'Cannot call additional methods after shutting down the SDK'
      end
    end

    def check_gate_fallback(user, gate_name)
      network_result = @net.check_gate(user, gate_name)
      if network_result.nil?
        config_result = ConfigResult.new()
        config_result.name = gate_name
        config_result.gate_value = false
        config_result.rule_id = nil
        return config_result
      end

      config_result = ConfigResult.new()
      config_result.name = network_result['name']
      config_result.gate_value = network_result['value']
      config_result.rule_id = network_result['rule_id']
      return config_result
    end

    def get_config_fallback(user, dynamic_config_name)
      network_result = @net.get_config(user, dynamic_config_name)
      if network_result.nil?
        config_result = ConfigResult.new()
        config_result.name = dynamic_config_name
        config_result.json_value = {}
        config_result.rule_id = nil
        return config_result
      end

      config_result = ConfigResult.new()
      config_result.name = network_result['name']
      config_result.json_value = network_result['value']
      config_result.rule_id = network_result['rule_id']
      return config_result
    end
  end