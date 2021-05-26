require 'concurrent'
require 'network'

class Statsig
    include Concurrent::Async

    def initialize(secret_key)
        super()
        @secret_key = secret_key
        @net = Network.new(secret_key, 'http://localhost:3006/v1')
    end
  
    def check_gate(gate_name)
      if !gate_name.is_a?(String) || gate_name.empty?
        raise "Invalid gate_name provided"
      end
  
      return @net.check_gate(gate_name)
    end
  end