require 'concurrent'
require 'network'
require 'statsig_event'
require 'statsig_logger'

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
    end
  
    def check_gate(gate_name)
      if !gate_name.is_a?(String) || gate_name.empty?
        raise "Invalid gate_name provided"
      end
  
      return @net.check_gate(gate_name)
    end

    def get_config(dyanmic_config_name)
      if !dyanmic_config_name.is_a?(String) || dyanmic_config_name.empty?
        raise "Invalid dyanmic_config_name provided"
      end

      return @net.get_config(dyanmic_config_name)
    end

    def download_config_specs
      return @net.download_config_specs()
    end

    def log_event(user, event_name, value = nil, metadata = nil)
      event = StatsigEvent.new(event_name)
      event.user = user
      event.value = value
      event.metadata = metadata
      event.statsig_metadata = @statsig_metadata
      @logger.log_event(event)
    end
  end