require 'statsig_event'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'
$layer_exposure_event = 'statsig::layer_exposure'

module Statsig
  class StatsigLogger
    def initialize(network, options)
      @network = network
      @events = []
      @background_flush = periodic_flush
      @options = options
    end

    def log_event(event)
      @events.push(event)
      if @events.length >= @options.logging_max_buffer_size
        flush
      end
    end

    def log_gate_exposure(user, gate_name, value, rule_id, secondary_exposures, eval_details)
      event = StatsigEvent.new($gate_exposure_event)
      event.user = user
      event.metadata = {
        'gate' => gate_name,
        'gateValue' => value.to_s,
        'ruleID' => rule_id,
      }
      event.statsig_metadata = Statsig.get_statsig_metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []

      safe_add_eval_details(eval_details, event)
      log_event(event)
    end

    def log_config_exposure(user, config_name, rule_id, secondary_exposures, eval_details)
      event = StatsigEvent.new($config_exposure_event)
      event.user = user
      event.metadata = {
        'config' => config_name,
        'ruleID' => rule_id,
      }
      event.statsig_metadata = Statsig.get_statsig_metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []

      safe_add_eval_details(eval_details, event)
      log_event(event)
    end

    def log_layer_exposure(user, layer, parameter_name, config_evaluation)
      exposures = config_evaluation.undelegated_sec_exps
      allocated_experiment = ''
      is_explicit = (config_evaluation.explicit_parameters&.include? parameter_name) || false
      if is_explicit
        allocated_experiment = config_evaluation.config_delegate
        exposures = config_evaluation.secondary_exposures
      end

      event = StatsigEvent.new($layer_exposure_event)
      event.user = user
      event.metadata = {
        'config' => layer.name,
        'ruleID' => layer.rule_id,
        'allocatedExperiment' => allocated_experiment,
        'parameterName' => parameter_name,
        'isExplicitParameter' => String(is_explicit),
      }
      event.statsig_metadata = Statsig.get_statsig_metadata
      event.secondary_exposures = exposures.is_a?(Array) ? exposures : []

      safe_add_eval_details(config_evaluation.evaluation_details, event)
      log_event(event)
    end

    def periodic_flush
      Thread.new do
        loop do
          sleep @options.logging_interval_seconds
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
      events_clone = @events
      @events = []
      flush_events = events_clone.map { |e| e.serialize }

      if closing
        @network.post_logs(flush_events)
      else
        Thread.new do
          @network.post_logs(flush_events)
        end
      end
    end

    def maybe_restart_background_threads
      if @background_flush.nil? or !@background_flush.alive?
        @background_flush = periodic_flush
      end
    end

    private

    def safe_add_eval_details(eval_details, event)
      if eval_details.nil?
        return
      end

      event.metadata['reason'] = eval_details.reason
      event.metadata['configSyncTime'] = eval_details.config_sync_time
      event.metadata['initTime'] = eval_details.init_time
      event.metadata['serverTime'] = eval_details.server_time
    end
  end
end