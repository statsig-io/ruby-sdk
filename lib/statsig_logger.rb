
require 'statsig_event'
require 'concurrent-ruby'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'
$layer_exposure_event = 'statsig::layer_exposure'
$diagnostics_event = 'statsig::diagnostics'
$ignored_metadata_keys = ['serverTime', 'configSyncTime', 'initTime', 'reason']
module Statsig
  class StatsigLogger
    def initialize(network, options, error_boundary)
      @network = network
      @events = []
      @options = options

      @logging_pool = Concurrent::ThreadPoolExecutor.new(
        name: 'statsig-logger',
        min_threads: @options.logger_threadpool_size,
        max_threads: @options.logger_threadpool_size,
        # max jobs pending before we start dropping
        max_queue: 100,
        fallback_policy: :discard
      )

      @error_boundary = error_boundary
      @background_flush = periodic_flush
      @deduper = Concurrent::Set.new()
      @interval = 0
      @flush_mutex = Mutex.new
    end

    def log_event(event)
      @events.push(event)
      if @events.length >= @options.logging_max_buffer_size
        flush_async
      end
    end

    def log_gate_exposure(user, gate_name, value, rule_id, secondary_exposures, eval_details, context = nil)
      event = StatsigEvent.new($gate_exposure_event)
      event.user = user
      metadata = {
        'gate' => gate_name,
        'gateValue' => value.to_s,
        'ruleID' => rule_id,
      }
      return false if not is_unique_exposure(user, $gate_exposure_event, metadata)
      event.metadata = metadata

      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []

      safe_add_eval_details(eval_details, event)
      safe_add_exposure_context(context, event)
      log_event(event)
    end

    def log_config_exposure(user, config_name, rule_id, secondary_exposures, eval_details, context = nil)
      event = StatsigEvent.new($config_exposure_event)
      event.user = user
      metadata = {
        'config' => config_name,
        'ruleID' => rule_id,
      }
      return false if not is_unique_exposure(user, $config_exposure_event, metadata)
      event.metadata = metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []

      safe_add_eval_details(eval_details, event)
      safe_add_exposure_context(context, event)
      log_event(event)
    end

    def log_layer_exposure(user, layer, parameter_name, config_evaluation, context = nil)
      exposures = config_evaluation.undelegated_sec_exps
      allocated_experiment = ''
      is_explicit = (config_evaluation.explicit_parameters&.include? parameter_name) || false
      if is_explicit
        allocated_experiment = config_evaluation.config_delegate
        exposures = config_evaluation.secondary_exposures
      end

      event = StatsigEvent.new($layer_exposure_event)
      event.user = user
      metadata = {
        'config' => layer.name,
        'ruleID' => layer.rule_id,
        'allocatedExperiment' => allocated_experiment,
        'parameterName' => parameter_name,
        'isExplicitParameter' => String(is_explicit),
      }
      return false if not is_unique_exposure(user, $layer_exposure_event, metadata)
      event.metadata = metadata
      event.secondary_exposures = exposures.is_a?(Array) ? exposures : []

      safe_add_eval_details(config_evaluation.evaluation_details, event)
      safe_add_exposure_context(context, event)
      log_event(event)
    end

    def log_diagnostics_event(diagnostics, user = nil)
      return if @options.disable_diagnostics_logging
      return if diagnostics.nil?

      event = StatsigEvent.new($diagnostics_event)
      event.user = user
      serialized = diagnostics.serialize_with_sampling
      return if serialized[:markers].empty?

      event.metadata = serialized
      log_event(event)
      diagnostics.clear_markers
    end

    def periodic_flush
      Thread.new do
        @error_boundary.capture(task: lambda {
          loop do
            sleep @options.logging_interval_seconds
            flush_async
            @interval += 1
            @deduper.clear if @interval % 2 == 0
          end
        })
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
      @flush_mutex.synchronize do
        if @events.length.zero?
          return
        end

        events_clone = @events
        @events = []
        flush_events = events_clone.map { |e| e.serialize }
        @network.post_logs(flush_events)
      end
    end

    def maybe_restart_background_threads
      if @background_flush.nil? || !@background_flush.alive?
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

    def safe_add_exposure_context(context, event)
      if context.nil?
        return
      end

      if context['is_manual_exposure']
        event.metadata['isManualExposure'] = 'true'
      end
    end

    def is_unique_exposure(user, event_name, metadata)
      return true if user.nil?
      @deduper.clear if @deduper.size > 10000
      custom_id_key = ''
      if user.custom_ids.is_a?(Hash)
        custom_id_key = user.custom_ids.values.join(',')
      end

      metadata_key = ''
      if metadata.is_a?(Hash)
        metadata_key = metadata.reject { |key, _| $ignored_metadata_keys.include?(key) }.values.join(',')
      end

      user_id_key = ''
      unless user.user_id.nil?
        user_id_key = user.user_id
      end
      key = [user_id_key, custom_id_key, event_name, metadata_key].join(',')

      return false if @deduper.include?(key)
      @deduper.add(key)
      true
    end
  end
end