require 'statsig_event'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'
$layer_exposure_event = 'statsig::layer_exposure'

module Statsig
  class StatsigLogger
    def initialize(network)
      @network = network
      @events = []
      @background_flush = periodic_flush
    end

    def log_event(event)
      @events.push(event)
      if @events.length >= 500
        flush
      end
    end

    def log_gate_exposure(user, gate_name, value, rule_id, secondary_exposures)
      event = StatsigEvent.new($gate_exposure_event)
      event.user = user
      event.metadata = {
        'gate' => gate_name,
        'gateValue' => value.to_s,
        'ruleID' => rule_id
      }
      event.statsig_metadata = Statsig.get_statsig_metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []
      log_event(event)
    end

    def log_config_exposure(user, config_name, rule_id, secondary_exposures)
      event = StatsigEvent.new($config_exposure_event)
      event.user = user
      event.metadata = {
        'config' => config_name,
        'ruleID' => rule_id
      }
      event.statsig_metadata = Statsig.get_statsig_metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []
      log_event(event)
    end

    def log_layer_exposure(user, config_name, rule_id, secondary_exposures, allocated_experiment)
      event = StatsigEvent.new($layer_exposure_event)
      event.user = user
      event.metadata = {
        'config' => config_name,
        'ruleID' => rule_id,
        'allocatedExperiment' => allocated_experiment
      }
      event.statsig_metadata = Statsig.get_statsig_metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []
      log_event(event)
    end

    def periodic_flush
      Thread.new do
        loop do
          sleep 60
          flush
        end
      end
    end

    def flush(closing = false)
      if closing
        @background_flush&.exit
      end
      if @events.length == 0
        return
      end
      flush_events = @events.map { |e| e.serialize }
      @events = []

      @network.post_logs(flush_events)
    end
  end
end