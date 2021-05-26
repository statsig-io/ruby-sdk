require 'concurrent'
require 'network'

class Statsig
    include Concurrent::Async

    def initialize(secret_key)
        super()
        if !secret_key.is_a?(String) || !secret_key.start_with?('secret-')
          raise 'Invalid secret key provided.  Provide your project secret key from the Statsig console'
        end
        @secret_key = secret_key
        @net = Network.new(secret_key, 'http://localhost:3006/v1')
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
  end