# typed: false
require 'net/http'
require 'uri'
require 'evaluation_details'
require 'id_list'
require 'concurrent-ruby'

module Statsig
  class SpecStore

    attr_accessor :last_config_sync_time
    attr_accessor :initial_config_sync_time
    attr_accessor :init_reason

    def initialize(network, options, error_callback, diagnostics, error_boundary, logger)
      @init_reason = EvaluationReason::UNINITIALIZED
      @network = network
      @options = options
      @error_callback = error_callback
      @last_config_sync_time = 0
      @initial_config_sync_time = 0
      @rulesets_sync_interval = options.rulesets_sync_interval
      @id_lists_sync_interval = options.idlists_sync_interval
      @rules_updated_callback = options.rules_updated_callback
      @specs = {
        :gates => {},
        :configs => {},
        :layers => {},
        :id_lists => {},
        :experiment_to_layer => {},
        :sdk_keys_to_app_ids => {}
      }
      @diagnostics = diagnostics
      @error_boundary = error_boundary
      @logger = logger

      @id_list_thread_pool = Concurrent::FixedThreadPool.new(
        options.idlist_threadpool_size,
        name: 'statsig-idlist',
        max_queue: 100,
        fallback_policy: :discard,
      )

      unless @options.bootstrap_values.nil?
        if !@options.data_store.nil?
          puts 'data_store gets priority over bootstrap_values. bootstrap_values will be ignored'
        else
          tracker = @diagnostics.track('bootstrap', 'process')
          begin
            if process_specs(options.bootstrap_values)
              @init_reason = EvaluationReason::BOOTSTRAP
            end
          rescue
            puts 'the provided bootstrapValues is not a valid JSON string'
          ensure
            tracker.end(success: @init_reason == EvaluationReason::BOOTSTRAP)
          end
        end
      end

      unless @options.data_store.nil?
        @options.data_store.init
        load_config_specs_from_storage_adapter
      end

      if @init_reason == EvaluationReason::UNINITIALIZED
        download_config_specs
      end

      @initial_config_sync_time = @last_config_sync_time == 0 ? -1 : @last_config_sync_time
      if !@options.data_store.nil?
        get_id_lists_from_adapter
      else
        get_id_lists_from_network
      end

      @config_sync_thread = spawn_sync_config_specs_thread
      @id_lists_sync_thread = spawn_sync_id_lists_thread
    end

    def is_ready_for_checks
      @last_config_sync_time != 0
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
      @specs[:gates].key?(gate_name)
    end

    def has_config?(config_name)
      @specs[:configs].key?(config_name)
    end

    def has_layer?(layer_name)
      @specs[:layers].key?(layer_name)
    end

    def get_gate(gate_name)
      return nil unless has_gate?(gate_name)
      @specs[:gates][gate_name]
    end

    def get_config(config_name)
      return nil unless has_config?(config_name)
      @specs[:configs][config_name]
    end

    def get_layer(layer_name)
      return nil unless has_layer?(layer_name)
      @specs[:layers][layer_name]
    end

    def get_id_list(list_name)
      @specs[:id_lists][list_name]
    end

    def has_sdk_key?(sdk_key)
      @specs[:sdk_keys_to_app_ids].key?(sdk_key)
    end

    def get_app_id_for_sdk_key(sdk_key)
      if sdk_key.nil?
        return nil
      end
      return nil unless has_sdk_key?(sdk_key)
      @specs[:sdk_keys_to_app_ids][sdk_key]
    end

    def get_raw_specs
      @specs
    end

    def maybe_restart_background_threads
      if @config_sync_thread.nil? || !@config_sync_thread.alive?
        @config_sync_thread = sync_config_specs
      end
      if @id_lists_sync_thread.nil? || !@id_lists_sync_thread.alive?
        @id_lists_sync_thread = sync_id_lists
      end
    end

    def sync_config_specs
      @diagnostics = Diagnostics.new('config_sync')
      if @options.data_store&.should_be_used_for_querying_updates(Interfaces::IDataStore::CONFIG_SPECS_KEY)
        load_config_specs_from_storage_adapter
      else
        download_config_specs
      end
      @logger.log_diagnostics_event(@diagnostics)
    end

    def sync_id_lists
      @diagnostics = Diagnostics.new('config_sync')
      if @options.data_store&.should_be_used_for_querying_updates(Interfaces::IDataStore::ID_LISTS_KEY)
        get_id_lists_from_adapter
      else
        get_id_lists_from_network
      end
      @logger.log_diagnostics_event(@diagnostics)
    end

    private

    def load_config_specs_from_storage_adapter
      tracker = @diagnostics.track('data_store_config_specs', 'fetch')
      cached_values = @options.data_store.get(Interfaces::IDataStore::CONFIG_SPECS_KEY)
      tracker.end(success: true)
      return if cached_values.nil?

      tracker = @diagnostics.track('data_store_config_specs', 'process')
      process_specs(cached_values, from_adapter: true)
      @init_reason = EvaluationReason::DATA_ADAPTER
      tracker.end(success: true)
    rescue StandardError
      # Fallback to network
      tracker.end(success: false)
      download_config_specs
    end

    def save_config_specs_to_storage_adapter(specs_string)
      if @options.data_store.nil?
        return
      end
      @options.data_store.set(Interfaces::IDataStore::CONFIG_SPECS_KEY, specs_string)
    end

    def spawn_sync_config_specs_thread
      if @options.disable_rulesets_sync
        return nil
      end

      Thread.new do
        @error_boundary.capture(task: lambda {
          loop do
            sleep @options.rulesets_sync_interval
            sync_config_specs
          end
        })
      end
    end

    def spawn_sync_id_lists_thread
      if @options.disable_idlists_sync
        return nil
      end

      Thread.new do
        @error_boundary.capture(task: lambda {
          loop do
            sleep @id_lists_sync_interval
            sync_id_lists
          end
        })
      end
    end
    def download_config_specs
      tracker = @diagnostics.track('download_config_specs', 'network_request')

      error = nil
      begin
        response, e = @network.post_helper('download_config_specs', JSON.generate({ 'sinceTime' => @last_config_sync_time }))
        code = response&.status.to_i
        if e.is_a? NetworkError
          code = e.http_code
        end
        tracker.end(statusCode: code, success: e.nil?, sdkRegion: response&.headers&.[]('X-Statsig-Region'))

        if e.nil?
          unless response.nil?
            tracker = @diagnostics.track('download_config_specs', 'process')
            if process_specs(response.body.to_s)
              @init_reason = EvaluationReason::NETWORK
            end
            tracker.end(success: @init_reason == EvaluationReason::NETWORK)

            @rules_updated_callback.call(response.body.to_s, @last_config_sync_time) unless response.body.nil? or @rules_updated_callback.nil?
          end

          nil
        else
          error = e
        end
      rescue StandardError => e
        error = e
      end

      @error_callback.call(error) unless error.nil? or @error_callback.nil?
    end

    def process_specs(specs_string, from_adapter: false)
      if specs_string.nil?
        return false
      end

      specs_json = JSON.parse(specs_string)
      return false unless specs_json.is_a? Hash

      @last_config_sync_time = specs_json['time'] || @last_config_sync_time
      return false unless specs_json['has_updates'] == true &&
        !specs_json['feature_gates'].nil? &&
        !specs_json['dynamic_configs'].nil? &&
        !specs_json['layer_configs'].nil?

      new_gates = {}
      new_configs = {}
      new_layers = {}
      new_exp_to_layer = {}

      specs_json['feature_gates'].each { |gate| new_gates[gate['name']] = gate }
      specs_json['dynamic_configs'].each { |config| new_configs[config['name']] = config }
      specs_json['layer_configs'].each { |layer| new_layers[layer['name']] = layer }

      if specs_json['layers'].is_a?(Hash)
        specs_json['layers'].each { |layer_name, experiments|
          experiments.each { |experiment_name| new_exp_to_layer[experiment_name] = layer_name }
        }
      end

      @specs[:gates] = new_gates
      @specs[:configs] = new_configs
      @specs[:layers] = new_layers
      @specs[:experiment_to_layer] = new_exp_to_layer
      @specs[:sdk_keys_to_app_ids] = specs_json['sdk_keys_to_app_ids'] || {}

      specs_json['diagnostics']

      unless from_adapter
        save_config_specs_to_storage_adapter(specs_string)
      end
      true
    end

    def get_id_lists_from_adapter
      tracker = @diagnostics.track('data_store_id_lists', 'fetch')
      cached_values = @options.data_store.get(Interfaces::IDataStore::ID_LISTS_KEY)
      return if cached_values.nil?

      tracker.end(success: true)
      id_lists = JSON.parse(cached_values)
      process_id_lists(id_lists, from_adapter: true)
    rescue StandardError
      # Fallback to network
      tracker.end(success: false)
      get_id_lists_from_network
    end

    def save_id_lists_to_adapter(id_lists_raw_json)
      if @options.data_store.nil?
        return
      end
      @options.data_store.set(Interfaces::IDataStore::ID_LISTS_KEY, id_lists_raw_json)
    end

    def get_id_lists_from_network
      tracker = @diagnostics.track('get_id_list_sources', 'network_request')
      response, e = @network.post_helper('get_id_lists', JSON.generate({ 'statsigMetadata' => Statsig.get_statsig_metadata }))
      code = response&.status.to_i
      if e.is_a? NetworkError
        code = e.http_code
      end
      success = e.nil? && !response.nil?
      tracker.end(statusCode: code, success: success, sdkRegion: response&.headers&.[]('X-Statsig-Region'))
      if !success
        return
      end

      begin
        server_id_lists = JSON.parse(response)
        process_id_lists(server_id_lists)
        save_id_lists_to_adapter(response.body.to_s)
      rescue
        # Ignored, will try again
      end
    end

    def process_id_lists(new_id_lists, from_adapter: false)
      local_id_lists = @specs[:id_lists]
      if !new_id_lists.is_a?(Hash) || !local_id_lists.is_a?(Hash)
        return
      end
      tasks = []

      tracker = @diagnostics.track(
        from_adapter ? 'data_store_id_lists' : 'get_id_list_sources',
        'process',
        { idListCount: new_id_lists.length }
      )

      if new_id_lists.empty?
        tracker.end(success: true)
        return
      end

      delete_lists = []
      local_id_lists.each do |list_name, list|
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

        tasks << Concurrent::Promise.execute(:executor => @id_list_thread_pool) do
          if from_adapter
            get_single_id_list_from_adapter(local_list)
          else
            download_single_id_list(local_list)
          end
        end
      end

      result = Concurrent::Promise.all?(*tasks).execute.wait(@id_lists_sync_interval)
      tracker.end(success: result.state == :fulfilled)
    end

    def get_single_id_list_from_adapter(list)
      tracker = @diagnostics.track('data_store_id_list', 'fetch', { url: list.url })
      cached_values = @options.data_store.get("#{Interfaces::IDataStore::ID_LISTS_KEY}::#{list.name}")
      tracker.end(success: true)
      content = cached_values.to_s
      process_single_id_list(list, content, from_adapter: true)
    rescue StandardError
      tracker.end(success: false)
      nil
    end

    def save_single_id_list_to_adapter(name, content)
      return if @options.data_store.nil?

      @options.data_store.set("#{Interfaces::IDataStore::ID_LISTS_KEY}::#{name}", content)
    end

    def download_single_id_list(list)
      nil unless list.is_a? IDList
      http = HTTP.headers({ 'Range' => "bytes=#{list&.size || 0}-" }).accept(:json)
      tracker = @diagnostics.track('get_id_list', 'network_request', { url: list.url })
      begin
        res = http.get(list.url)
        tracker.end(statusCode: res.status.code, success: res.status.success?)
        nil unless res.status.success?
        content_length = Integer(res['content-length'])
        nil if content_length.nil? || content_length <= 0
        content = res.body.to_s
        success = process_single_id_list(list, content, content_length)
        save_single_id_list_to_adapter(list.name, content) unless success.nil? || !success
      rescue
        tracker.end(success: false)
        nil
      end
    end

    def process_single_id_list(list, content, content_length = nil, from_adapter: false)
      false unless list.is_a? IDList
      begin
        tracker = @diagnostics.track(from_adapter ? 'data_store_id_list' : 'get_id_list', 'process', { url: list.url })
        unless content.is_a?(String) && (content[0] == '-' || content[0] == '+')
          @specs[:id_lists].delete(list.name)
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
      rescue
        tracker.end(success: false)
        return false
      end
    end
  end
end