require 'constants'
require 'statsig_event'
require 'ttl_set'
require 'concurrent-ruby'
require 'hash_utils'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'
$layer_exposure_event = 'statsig::layer_exposure'
$diagnostics_event = 'statsig::diagnostics'
$ignored_metadata_keys = [:serverTime, :configSyncTime, :initTime, :reason]

class EntityType
  GATE = "gate"
  CONFIG = "config"
  LAYER = "layer"
end

module Statsig
  class StatsigLogger
    def initialize(network, options, error_boundary, sdk_configs)
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
      @deduper = Concurrent::Set.new
      @sampling_key_set = Statsig::TTLSet.new
      @interval = 0
      @flush_mutex = Mutex.new
      @debug_info = nil
      @sdk_configs = sdk_configs
    end

    def log_event(event)
      @events.push(event)
      if @events.length >= @options.logging_max_buffer_size
        flush_async
      end
    end

    def log_gate_exposure(user, result, context = nil)
      should_log, logged_sampling_rate, shadow_logged = determine_sampling(EntityType::GATE, result.name, result, user)
      return unless should_log
      event = StatsigEvent.new($gate_exposure_event)
      event.user = user
      metadata = {
        gate: result.name,
        gateValue: result.gate_value.to_s,
        ruleID: result.rule_id || Statsig::Const::EMPTY_STR,
      }
      if result.config_version != nil
        metadata[:configVersion] = result.config_version.to_s
      end
      if @debug_info != nil
        metadata[:debugInfo] = @debug_info
      end
      return false if not is_unique_exposure(user, $gate_exposure_event, metadata)
      event.metadata = metadata
      event.statsig_metadata = {}

      event.secondary_exposures = result.secondary_exposures.is_a?(Array) ? result.secondary_exposures : []

      safe_add_eval_details(result.evaluation_details, event)
      safe_add_exposure_context(context, event)
      safe_add_sampling_metadata(event, logged_sampling_rate, shadow_logged)
      log_event(event)
    end

    def log_config_exposure(user, result, context = nil)
      should_log, logged_sampling_rate, shadow_logged = determine_sampling(EntityType::CONFIG, result.name, result, user)
      return unless should_log
      event = StatsigEvent.new($config_exposure_event)
      event.user = user
      metadata = {
        config: result.name,
        ruleID: result.rule_id || Statsig::Const::EMPTY_STR,
        rulePassed: result.gate_value.to_s,
      }
      if result.config_version != nil
        metadata[:configVersion] = result.config_version.to_s
      end
      if @debug_info != nil
        metadata[:debugInfo] = @debug_info
      end
      return false if not is_unique_exposure(user, $config_exposure_event, metadata)
      event.metadata = metadata
      event.secondary_exposures = result.secondary_exposures.is_a?(Array) ? result.secondary_exposures : []
      event.statsig_metadata = {}

      safe_add_eval_details(result.evaluation_details, event)
      safe_add_exposure_context(context, event)
      safe_add_sampling_metadata(event, logged_sampling_rate, shadow_logged)
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

      should_log, logged_sampling_rate, shadow_logged = determine_sampling(EntityType::LAYER, config_evaluation.name, config_evaluation, user, allocated_experiment, parameter_name)
      return unless should_log

      event = StatsigEvent.new($layer_exposure_event)
      event.user = user
      metadata = {
        config: layer.name,
        ruleID: layer.rule_id || Statsig::Const::EMPTY_STR,
        allocatedExperiment: allocated_experiment,
        parameterName: parameter_name,
        isExplicitParameter: String(is_explicit)
      }
      if config_evaluation.config_version != nil
        metadata[:configVersion] = config_evaluation.config_version.to_s
      end
      if @debug_info != nil
        metadata[:debugInfo] = @debug_info
      end
      return false unless is_unique_exposure(user, $layer_exposure_event, metadata)
      event.metadata = metadata
      event.secondary_exposures = exposures.is_a?(Array) ? exposures : []
      event.statsig_metadata = {}

      safe_add_eval_details(config_evaluation.evaluation_details, event)
      safe_add_exposure_context(context, event)
      safe_add_sampling_metadata(event, logged_sampling_rate, shadow_logged)
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
      @sampling_key_set.shutdown
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
        @network.post_logs(flush_events, @error_boundary)
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

    def safe_add_sampling_metadata(event, logged_sampling_rate = nil, shadow_logged = nil)
      unless logged_sampling_rate.nil?
        event.statsig_metadata["samplingRate"] = logged_sampling_rate
      end

      unless shadow_logged.nil?
        event.statsig_metadata["shadowLogged"] = shadow_logged
      end

      event.statsig_metadata["samplingMode"] = @sdk_configs.get_config_string_value("sampling_mode")
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

    def determine_sampling(type, name, result, user, exp_name = "", param_name = "")
      begin
        shadow_should_log, logged_sampling_rate = true, nil
        env = @options.environment&.dig(:tier)
        sampling_mode = @sdk_configs.get_config_string_value("sampling_mode")
        special_case_sampling_rate = @sdk_configs.get_config_int_value("special_case_sampling_rate")
        special_case_rules = ["disabled", "default", ""]

        if sampling_mode.nil? || sampling_mode == "none" || env != "production"
          return true, nil, nil
        end

        return true, nil, nil if result.forward_all_exposures
        return true, nil, nil if result.rule_id.end_with?(":override", ":id_override")
        return true, nil, nil if result.has_seen_analytical_gates

        sampling_set_key = "#{name}_#{result.rule_id}"
        unless @sampling_key_set.contains?(sampling_set_key)
          @sampling_key_set.add(sampling_set_key)
          return true, nil, nil
        end

        should_sample = result.sampling_rate || special_case_rules.include?(result.rule_id)
        unless should_sample
          return true, nil, nil
        end

        exposure_key = ""
        case type
        when EntityType::GATE
          exposure_key = Statsig::HashUtils.compute_dedupe_key_for_gate(name, result.rule_id, result.gate_value, user.user_id, user.custom_ids)
        when EntityType::CONFIG
          exposure_key = Statsig::HashUtils.compute_dedupe_key_for_config(name, result.rule_id, user.user_id, user.custom_ids)
        when EntityType::LAYER
          exposure_key = Statsig::HashUtils.compute_dedupe_key_for_layer(name, exp_name, param_name, result.rule_id, user.user_id, user.custom_ids)
        end

        if result.sampling_rate
          shadow_should_log = Statsig::HashUtils.is_hash_in_sampling_rate(exposure_key, result.sampling_rate)
          logged_sampling_rate = result.sampling_rate
        elsif special_case_rules.include?(result.rule_id) && special_case_sampling_rate
          shadow_should_log = Statsig::HashUtils.is_hash_in_sampling_rate(exposure_key, special_case_sampling_rate)
          logged_sampling_rate = special_case_sampling_rate
        end

        shadow_logged = if logged_sampling_rate.nil?
                          nil
                        else
                          shadow_should_log ? "logged" : "dropped"
                        end
        if sampling_mode == "on"
          return shadow_should_log, logged_sampling_rate, shadow_logged
        elsif sampling_mode == "shadow"
          return true, logged_sampling_rate, shadow_logged
        end

        return true, nil, nil
      rescue => e
        @error_boundary.log_exception(e, "__determine_sampling")
        return true, nil, nil
      end
    end

  end
end
