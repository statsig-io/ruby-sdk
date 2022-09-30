module Statsig

  module EvaluationReason
    NETWORK = "Network"
    LOCAL_OVERRIDE = "LocalOverride"
    UNRECOGNIZED = "Unrecognized"
    UNINITIALIZED = "Uninitialized"
    BOOTSTRAP = "Bootstrap"
    DATA_ADAPTER = "DataAdapter"
  end

  class EvaluationDetails
    attr_accessor :config_sync_time
    attr_accessor :init_time
    attr_accessor :reason
    attr_accessor :server_time

    def initialize(config_sync_time, init_time, reason)
      @config_sync_time = config_sync_time
      @init_time = init_time
      @reason = reason
      @server_time = (Time.now.to_i * 1000).to_s
    end

    def self.unrecognized(config_sync_time, init_time)
      EvaluationDetails.new(config_sync_time, init_time, EvaluationReason::UNRECOGNIZED)
    end

    def self.uninitialized
      EvaluationDetails.new(0, 0, EvaluationReason::UNINITIALIZED)
    end

    def self.network(config_sync_time, init_time)
      EvaluationDetails.new(config_sync_time, init_time, EvaluationReason::NETWORK)
    end

    def self.local_override(config_sync_time, init_time)
      EvaluationDetails.new(config_sync_time, init_time, EvaluationReason::LOCAL_OVERRIDE)
    end
  end
end