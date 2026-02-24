require 'concurrent-ruby'
require 'net/http'
require 'uri'
require_relative 'api_config'
require_relative 'evaluation_details'
require_relative 'hash_utils'
require_relative 'id_list'

module Statsig
  class SpecStore
    attr_accessor :last_config_sync_time
    attr_accessor :initial_config_sync_time
    attr_accessor :init_reason
    attr_accessor :gates
    attr_accessor :configs
    attr_accessor :layers
    attr_accessor :id_lists
    attr_accessor :experiment_to_layer
    attr_accessor :sdk_keys_to_app_ids
    attr_accessor :hashed_sdk_keys_to_app_ids
    attr_accessor :unsupported_configs
    attr_accessor :cmab_configs
    attr_accessor :overrides
    attr_accessor :override_rules

    def initialize(network, options, error_callback, diagnostics, error_boundary, logger, secret_key, sdk_config)
      @init_reason = EvaluationReason::UNINITIALIZED
      @network = network
      @options = options
      @error_callback = error_callback
      @last_config_sync_time = 0
      @initial_config_sync_time = 0
      @rulesets_sync_interval = options.rulesets_sync_interval
      @id_lists_sync_interval = options.idlists_sync_interval
      @rules_updated_callback = options.rules_updated_callback
      @gates = {}
      @configs = {}
      @layers = {}
      @cmab_configs = {}
      @condition_map = {}
      @id_lists = {}
      @experiment_to_layer = {}
      @sdk_keys_to_app_ids = {}
      @hashed_sdk_keys_to_app_ids = {}
      @overrides = {}
      @override_rules = {}
      @diagnostics = diagnostics
      @error_boundary = error_boundary
      @logger = logger
      @secret_key = secret_key
      @unsupported_configs = Set.new
      @sdk_configs = sdk_config

      startTime = (Time.now.to_f * 1000).to_i

      @id_list_thread_pool = Concurrent::FixedThreadPool.new(
        options.idlist_threadpool_size,
        name: 'statsig-idlist',
        max_queue: 100,
        fallback_policy: :discard
      )

      unless @options.bootstrap_values.nil?
        if !@options.data_store.nil?
          puts 'data_store gets priority over bootstrap_values. bootstrap_values will be ignored'
        else
          tracker = @diagnostics.track('initialize','bootstrap', 'process')
          begin
            if process_specs(options.bootstrap_values).nil?
              @init_reason = EvaluationReason::BOOTSTRAP
            end
          rescue StandardError
            puts 'the provided bootstrapValues is not a valid JSON string'
          ensure
            tracker.end(success: @init_reason == EvaluationReason::BOOTSTRAP)
          end
        end
      end

      failure_details = nil

      unless @options.data_store.nil?
        @options.data_store.init
        failure_details = load_config_specs_from_storage_adapter('initialize')
      end

      if @init_reason == EvaluationReason::UNINITIALIZED
        failure_details = download_config_specs('initialize')
      end

      @initial_config_sync_time = @last_config_sync_time == 0 ? -1 : @last_config_sync_time
      if !@options.data_store.nil?
        get_id_lists_from_adapter('initialize')
      else
        get_id_lists_from_network('initialize')
      end

      @config_sync_thread = spawn_sync_config_specs_thread
      @id_lists_sync_thread = spawn_sync_id_lists_thread
      endTime = (Time.now.to_f * 1000).to_i
      @initialization_details = {duration: endTime - startTime, isSDKReady: true, configSpecReady: @init_reason != EvaluationReason::UNINITIALIZED, failureDetails: failure_details}
    end

    def is_ready_for_checks
      @last_config_sync_time != 0
    end

    def get_initialization_details
      @initialization_details
    end

    def shutdown
      @config_sync_thread&.exit
      @id_lists_sync_thread&.exit
      @id_list_thread_pool.shutdown
      @id_list_thread_pool.wait_for_termination(timeout = 3)
      unless @options.data_store.nil?
        @options.data_store.shutdown
      end
    end

    def has_gate?(gate_name)
      @gates.key?(gate_name.to_sym)
    end

    def has_config?(config_name)
      @configs.key?(config_name.to_sym)
    end

    def has_layer?(layer_name)
      @layers.key?(layer_name.to_sym)
    end

    def has_cmab_config?(config_name)
      if @cmab_configs.nil?
        return false
      end
      @cmab_configs.key?(config_name.to_sym)
    end

    def get_gate(gate_name)
      gate_sym = gate_name.to_sym
      return nil unless has_gate?(gate_sym)
      @gates[gate_sym]
    end

    def get_config(config_name)
      config_sym = config_name.to_sym
      return nil unless has_config?(config_sym)

      @configs[config_sym]
    end

    def get_layer(layer_name)
      layer_sym = layer_name.to_sym
      return nil unless has_layer?(layer_sym)

      @layers[layer_sym]
    end

    def get_cmab_config(config_name)
      config_sym = config_name.to_sym
      return nil unless has_cmab_config?(config_sym)
      @cmab_configs[config_sym]
    end

    def get_condition(condition_hash)
      @condition_map[condition_hash.to_sym]
    end

    def get_id_list(list_name)
      @id_lists[list_name]
    end

    def has_sdk_key?(sdk_key)
      @sdk_keys_to_app_ids.key?(sdk_key)
    end

    def has_hashed_sdk_key?(hashed_sdk_key)
      @hashed_sdk_keys_to_app_ids.key?(hashed_sdk_key)
    end

    def get_app_id_for_sdk_key(sdk_key)
      if sdk_key.nil?
        return nil
      end

      hashed_sdk_key = Statsig::HashUtils.djb2(sdk_key).to_sym
      if has_hashed_sdk_key?(hashed_sdk_key)
        return @hashed_sdk_keys_to_app_ids[hashed_sdk_key]
      end

      key = sdk_key.to_sym
      return nil unless has_sdk_key?(key)

      @sdk_keys_to_app_ids[key]
    end

    def maybe_restart_background_threads
      if @config_sync_thread.nil? || !@config_sync_thread.alive?
        @config_sync_thread = spawn_sync_config_specs_thread
      end
      if @id_lists_sync_thread.nil? || !@id_lists_sync_thread.alive?
        @id_lists_sync_thread = spawn_sync_id_lists_thread
      end
    end

    def sync_config_specs
      if @options.data_store&.should_be_used_for_querying_updates(Interfaces::IDataStore::CONFIG_SPECS_V2_KEY)
        load_config_specs_from_storage_adapter('config_sync')
      else
        download_config_specs('config_sync')
      end
      @logger.log_diagnostics_event(@diagnostics, 'config_sync')
    end

    def sync_id_lists
      if @options.data_store&.should_be_used_for_querying_updates(Interfaces::IDataStore::ID_LISTS_KEY)
        get_id_lists_from_adapter('config_sync')
      else
        get_id_lists_from_network('config_sync')
      end
      @logger.log_diagnostics_event(@diagnostics, 'config_sync')
    end

    private

    def load_config_specs_from_storage_adapter(context)
      tracker = @diagnostics.track(context, 'data_store_config_specs', 'fetch')
      cached_values = @options.data_store.get(Interfaces::IDataStore::CONFIG_SPECS_V2_KEY)
      tracker.end(success: true)
      return if cached_values.nil?

      tracker = @diagnostics.track(context, 'data_store_config_specs', 'process')
      failure_details = process_specs(cached_values, from_adapter: true)
      if failure_details.nil?
        @init_reason = EvaluationReason::DATA_ADAPTER
        tracker.end(success: true)
      else
        tracker.end(success: false)
        return download_config_specs(context)
      end
      return failure_details
    rescue StandardError
      # Fallback to network
      tracker.end(success: false)
      return download_config_specs(context)
    end

    def save_rulesets_to_storage_adapter(rulesets_string)
      if @options.data_store.nil?
        return
      end

      @options.data_store.set(Interfaces::IDataStore::CONFIG_SPECS_V2_KEY, rulesets_string)
    end

    def spawn_sync_config_specs_thread
      if @options.disable_rulesets_sync
        return nil
      end

      Thread.new do
        @error_boundary.capture() do
          loop do
            sleep @options.rulesets_sync_interval
            sync_config_specs
          end
        end
      end
    end

    def spawn_sync_id_lists_thread
      if @options.disable_idlists_sync
        return nil
      end

      Thread.new do
        @error_boundary.capture() do
          loop do
            sleep @id_lists_sync_interval
            sync_id_lists
          end
        end
      end
    end

    def download_config_specs(context)
      tracker = @diagnostics.track(context, 'download_config_specs', 'network_request')

      error = nil
      failure_details = nil
      begin
        response, e = @network.download_config_specs(@last_config_sync_time)
        code = response&.status.to_i
        if e.is_a? NetworkError
          code = e.http_code
          failure_details = {statusCode: code, exception: e, reason: "CONFIG_SPECS_NETWORK_ERROR"}
        end
        tracker.end(statusCode: code, success: e.nil?, sdkRegion: response&.headers&.[]('X-Statsig-Region'))

        if e.nil?
          unless response.nil?
            tracker = @diagnostics.track(context, 'download_config_specs', 'process')
            failure_details = process_specs(response.body.to_s)
            if failure_details.nil?
              @init_reason = EvaluationReason::NETWORK
            end
            tracker.end(success: @init_reason == EvaluationReason::NETWORK)

            unless response.body.nil? or @rules_updated_callback.nil?
              @rules_updated_callback.call(response.body.to_s,
                                           @last_config_sync_time)
            end
          end
        else
          error = e
        end
      rescue StandardError => e
        failure_details = {exception: e, reason: "INTERNAL_ERROR"}
        error = e
      end

      @error_callback.call(error) unless error.nil? or @error_callback.nil?
      return failure_details
    end

    def process_specs(specs_string, from_adapter: false)
      if specs_string.nil?
        return {reason: "EMPTY_SPEC"}
      end

      begin
        specs_json = JSON.parse(specs_string, { symbolize_names: true })
        return {reason: "PARSE_RESPONSE_ERROR"} unless specs_json.is_a? Hash

        hashed_sdk_key_used = specs_json[:hashed_sdk_key_used]
        unless hashed_sdk_key_used.nil? or hashed_sdk_key_used == Statsig::HashUtils.djb2(@secret_key)
          @error_boundary.log_exception(Statsig::InvalidSDKKeyResponse.new)
          return {reason: "PARSE_RESPONSE_ERROR"}
        end

        new_specs_sync_time = specs_json[:time]
        if new_specs_sync_time.nil? \
          || new_specs_sync_time < @last_config_sync_time \
          || specs_json[:has_updates] != true \
          || specs_json[:feature_gates].nil? \
          || specs_json[:dynamic_configs].nil? \
          || specs_json[:layer_configs].nil?
          return {reason: "PARSE_RESPONSE_ERROR"}
        end

        @last_config_sync_time = new_specs_sync_time
        @unsupported_configs.clear

        specs_json[:diagnostics]&.each { |key, value| @diagnostics.sample_rates[key.to_s] = value }

        @gates = specs_json[:feature_gates]
        @configs = specs_json[:dynamic_configs]
        @layers = specs_json[:layer_configs]
        @cmab_configs = specs_json[:cmab_configs]
        @condition_map = specs_json[:condition_map]
        @experiment_to_layer = specs_json[:experiment_to_layer]
        @sdk_keys_to_app_ids = specs_json[:sdk_keys_to_app_ids] || {}
        @hashed_sdk_keys_to_app_ids = specs_json[:hashed_sdk_keys_to_app_ids] || {}
        @sdk_configs.set_flags(specs_json[:sdk_flags])
        @sdk_configs.set_configs(specs_json[:sdk_configs])
        @overrides = specs_json[:overrides] || {}
        @override_rules = specs_json[:override_rules] || {}

        unless from_adapter
          save_rulesets_to_storage_adapter(specs_string)
        end
      rescue StandardError => e
        return {reason: "PARSE_RESPONSE_ERROR"}
      end
      nil
    end

    def get_id_lists_from_adapter(context)
      tracker = @diagnostics.track(context, 'data_store_id_lists', 'fetch')
      cached_values = @options.data_store.get(Interfaces::IDataStore::ID_LISTS_KEY)
      return if cached_values.nil?

      tracker.end(success: true)
      id_lists = JSON.parse(cached_values)
      process_id_lists(id_lists, context, from_adapter: true)
    rescue StandardError
      # Fallback to network
      tracker.end(success: false)
      get_id_lists_from_network(context)
    end

    def save_id_lists_to_adapter(id_lists_raw_json)
      if @options.data_store.nil?
        return
      end

      @options.data_store.set(Interfaces::IDataStore::ID_LISTS_KEY, id_lists_raw_json)
    end

    def get_id_lists_from_network(context)
      tracker = @diagnostics.track(context, 'get_id_list_sources', 'network_request')
      response, e = @network.get_id_lists
      code = response&.status.to_i
      if e.is_a? NetworkError
        code = e.http_code
      end
      success = e.nil? && !response.nil?
      tracker.end(statusCode: code, success: success, sdkRegion: response&.headers&.[]('X-Statsig-Region'))
      unless success
        return
      end

      begin
        server_id_lists = JSON.parse(response)
        process_id_lists(server_id_lists, context)
        save_id_lists_to_adapter(response.body.to_s)
      rescue StandardError
        # Ignored, will try again
      end
    end

    def process_id_lists(new_id_lists, context, from_adapter: false)
      local_id_lists = @id_lists
      if !new_id_lists.is_a?(Hash) || !local_id_lists.is_a?(Hash)
        return
      end

      tasks = []

      tracker = @diagnostics.track(context,
        from_adapter ? 'data_store_id_lists' : 'get_id_list_sources',
        'process',
        { idListCount: new_id_lists.length }
      )

      if new_id_lists.empty?
        tracker.end(success: true)
        return
      end

      delete_lists = []
      local_id_lists.each do |list_name, _list|
        unless new_id_lists.key? list_name
          delete_lists.push list_name
        end
      end
      delete_lists.each do |list_name|
        local_id_lists.delete list_name
      end

      new_id_lists.each do |list_name, list|
        new_list = IDList.new(list)
        local_list = get_id_list(list_name)

        unless local_list.is_a? IDList
          local_list = IDList.new(list)
          local_list.size = 0
          local_id_lists[list_name] = local_list
        end

        # skip if server list is invalid
        if new_list.url.nil? || new_list.creation_time < local_list.creation_time || new_list.file_id.nil?
          next
        end

        # reset local list if server list returns a newer file
        if new_list.file_id != local_list.file_id && new_list.creation_time >= local_list.creation_time
          local_list = IDList.new(list)
          local_list.size = 0
          local_id_lists[list_name] = local_list
        end

        # skip if server list is no bigger than local list, which means nothing new to read
        if new_list.size <= local_list.size
          next
        end

        tasks << Concurrent::Promise.execute(executor: @id_list_thread_pool) do
          if from_adapter
            get_single_id_list_from_adapter(local_list, context)
          else
            download_single_id_list(local_list, context)
          end
        end
      end

      result = Concurrent::Promise.all?(*tasks).execute.wait(@id_lists_sync_interval)
      tracker.end(success: result.state == :fulfilled)
    end

    def get_single_id_list_from_adapter(list, context)
      tracker = @diagnostics.track(context, 'data_store_id_list', 'fetch', { url: list.url })
      cached_values = @options.data_store.get("#{Interfaces::IDataStore::ID_LISTS_KEY}::#{list.name}")
      tracker.end(success: true)
      content = cached_values.to_s
      process_single_id_list(list, context, content, from_adapter: true)
    rescue StandardError
      tracker.end(success: false)
      nil
    end

    def save_single_id_list_to_adapter(name, content)
      return if @options.data_store.nil?

      @options.data_store.set("#{Interfaces::IDataStore::ID_LISTS_KEY}::#{name}", content)
    end

    def download_single_id_list(list, context)
      nil unless list.is_a? IDList
      http = HTTP.headers({ 'Range' => "bytes=#{list&.size || 0}-" }).accept(:json)
      tracker = @diagnostics.track(context, 'get_id_list', 'network_request', { url: list.url })
      begin
        res = http.get(list.url)
        tracker.end(statusCode: res.status.code, success: res.status.success?)
        nil unless res.status.success?
        content_length = Integer(res['content-length'])
        nil if content_length.nil? || content_length <= 0
        content = res.body.to_s
        success = process_single_id_list(list, context, content, content_length)
        save_single_id_list_to_adapter(list.name, content) unless success.nil? || !success
      rescue StandardError
        tracker.end(success: false)
        nil
      end
    end

    def process_single_id_list(list, context, content, content_length = nil, from_adapter: false)
      false unless list.is_a? IDList
      begin
        tracker = @diagnostics.track(context, from_adapter ? 'data_store_id_list' : 'get_id_list', 'process', { url: list.url })
        unless content.is_a?(String) && (content[0] == '-' || content[0] == '+')
          @id_lists.delete(list.name)
          tracker.end(success: false)
          return false
        end
        ids_clone = list.ids # clone the list, operate on the new list, and swap out the old list, so the operation is thread-safe
        lines = content.split(/\r?\n/)
        lines.each do |li|
          line = li.strip
          next if line.length <= 1

          op = line[0]
          id = line[1..line.length]
          if op == '+'
            ids_clone.add(id)
          elsif op == '-'
            ids_clone.delete(id)
          end
        end
        list.ids = ids_clone
        list.size = if content_length.nil?
                      list.size + content.bytesize
                    else
                      list.size + content_length
                    end
        tracker.end(success: true)
        return true
      rescue StandardError
        tracker.end(success: false)
        return false
      end
    end
  end
end
