require 'constants'
require 'statsig_event'
require 'concurrent-ruby'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'
$layer_exposure_event = 'statsig::layer_exposure'
$diagnostics_event = 'statsig::diagnostics'
$ignored_metadata_keys = [:serverTime, :configSyncTime, :initTime, :reason]
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
      @debug_info = nil
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
        gate: gate_name,
        gateValue: value.to_s,
        ruleID: rule_id || Statsig::Const::EMPTY_STR,
      }
      if @debug_info != nil
        metadata[:debugInfo] = @debug_info
      end
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
        config: config_name,
        ruleID: rule_id || Statsig::Const::EMPTY_STR,
      }
      if @debug_info != nil
        metadata[:debugInfo] = @debug_info
      end
      return false if not is_unique_exposure(user, $config_exposure_event, metadata)
      event.metadata = metadata
      event.secondary_exposures = secondary_exposures.is_a?(Array) ? secondary_exposures : []

      safe_add_eval_details(eval_details, event)
      safe_add_exposure_context(context, event)
      log_event(event)
    end

    def log_layer_exposure(user, layer, parameter_name, config_evaluation, context = nil)
      exposures = config_evaluation.undelegated_sec_exps || []
      allocated_experiment = Statsig::Const::EMPTY_STR
      is_explicit = (config_evaluation.explicit_parameters&.include? parameter_name) || false
      if is_explicit
        allocated_experiment = config_evaluation.config_delegate
        exposures = config_evaluation.secondary_exposures
      end

      event = StatsigEvent.new($layer_exposure_event)
      event.user = user
      metadata = {
        config: layer.name,
        ruleID: layer.rule_id || Statsig::Const::EMPTY_STR,
        allocatedExperiment: allocated_experiment,
        parameterName: parameter_name,
        isExplicitParameter: String(is_explicit)
      }
      if @debug_info != nil
        metadata[:debugInfo] = @debug_info
      end
      return false unless is_unique_exposure(user, $layer_exposure_event, metadata)
      event.metadata = metadata
      event.secondary_exposures = exposures.is_a?(Array) ? exposures : []

      safe_add_eval_details(config_evaluation.evaluation_details, event)
      safe_add_exposure_context(context, event)
      log_event(event)
    end

    def log_diagnostics_event(diagnostics, context, user = nil)
      return if diagnostics.nil?
      if @options.disable_diagnostics_logging
        diagnostics.clear_markers(context)
        return
      end

      event = StatsigEvent.new($diagnostics_event)
      event.user = user
      serialized = diagnostics.serialize_with_sampling(context)
      diagnostics.clear_markers(context)
      return if serialized[:markers].empty?

      event.metadata = serialized
      log_event(event)
    end

    def periodic_flush
      Thread.new do
        @error_boundary.capture() do
          loop do
            sleep @options.logging_interval_seconds
            flush_async
            @interval += 1
            @deduper.clear if @interval % 2 == 0
          end
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
      @flush_mutex.synchronize do
        return if @events.empty?
    
        events_clone = @events
        @events = []
        serialized_events = events_clone.map(&:serialize)
    
        serialized_events.each_slice(@options.logging_max_buffer_size) do |batch|
          @network.post_logs(batch, @error_boundary)
        end
      end
    end
    

    def maybe_restart_background_threads
      if @background_flush.nil? || !@background_flush.alive?
        @background_flush = periodic_flush
      end
    end

    def set_debug_info(debug_info)
      @debug_info = debug_info
    end

    private

    def safe_add_eval_details(eval_details, event)
      if eval_details.nil?
        return
      end

      event.metadata[:reason] = eval_details.reason
      event.metadata[:configSyncTime] = eval_details.config_sync_time
      event.metadata[:initTime] = eval_details.init_time
      event.metadata[:serverTime] = eval_details.server_time
    end

    def safe_add_exposure_context(context, event)
      if context.nil?
        return
      end

      if context[:is_manual_exposure]
        event.metadata[:isManualExposure] = 'true'
      end
    end

    def is_unique_exposure(user, event_name, metadata)
      return true if user.nil?
      @deduper.clear if @deduper.size > 10000

      user_key = user.user_key

      metadata_key = ''
      if metadata.is_a?(Hash)
        metadata_key = metadata.reject { |key, _| $ignored_metadata_keys.include?(key) }.values.join(',')
      end

      key = [user_key, event_name, metadata_key].join(',')

      return false if @deduper.include?(key)
      @deduper.add(key)
      true
    end
  end
end
