require 'concurrent'
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
          raise 'Invalid secret key provided.  Provide your project secret key from the Statsig console'
        end
        @secret_key = secret_key
        # 'http://localhost:3006/v1'
        @net = Network.new(secret_key, 'https://api.statsig.com/v1/')
        @statsig_metadata = {
          'sdkType' => 'ruby-server',
          'sdkVersion' => Gem::Specification::load('statsig.gemspec'),
        }
        @logger = StatsigLogger.new(@net, @statsig_metadata)

        downloaded_specs = @net.download_config_specs
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
      res = @evaluator.check_gate(user, gate_name)

      if res.nil?
        return false
      end

      return res[:gate_value]
    end

    def get_config(user, dynamic_config_name)
      if !user.nil? && !user.instance_of?(StatsigUser)
        raise 'Must provide a valid StatsigUser or nil'
      end
      if !dynamic_config_name.is_a?(String) || dynamic_config_name.empty?
        raise "Invalid dynamic_config_name provided"
      end

      res = @evaluator.get_config(user, dynamic_config_name)

      if res.nil?
        return @net.get_config(user, dynamic_config_name)
      end

      res[:config_value]
    end

    def log_event(user, event_name, value = nil, metadata = nil)
      if !user.nil? && !user.instance_of?(StatsigUser)
        raise 'Must provide a valid StatsigUser or nil'
      end
      event = StatsigEvent.new(event_name)
      event.user = user&.serialize
      event.value = value
      event.metadata = metadata
      event.statsig_metadata = @statsig_metadata
      @logger.log_event(event)
    end

    def shutdown
      @logger.flush
      @polling_thread&.exit
    end
  end