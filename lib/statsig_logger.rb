# typed: true
require 'statsig_event'
require 'concurrent-ruby'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'
$layer_exposure_event = 'statsig::layer_exposure'

module Statsig
  class StatsigLogger
    def initialize(network, options)
      @network = network
      @events = []
      @options = options

      @logging_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: [2, Concurrent.processor_count].min,
        max_threads: [2, Concurrent.processor_count].max,
        # max jobs pending before we start dropping
        max_queue:   [2, Concurrent.processor_count].max * 5,
        fallback_policy: :discard,
      )

      @background_flush = periodic_flush
    end

    def log_event(event)
      @events.push(event)
      if @events.length >= @options.logging_max_buffer_size
        flush_async
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

    def shutdown
      @background_flush&.exit
      @logging_pool.shutdown
      @logging_pool.wait_for_termination(timeout = 3)
      flush
    end

    def flush_async
      @logging_pool.post do
        flush
      end
    end

    def flush
      if @events.length == 0
        return
      end
      events_clone = @events
      @events = []
      flush_events = events_clone.map { |e| e.serialize }

      @network.post_logs(flush_events)
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