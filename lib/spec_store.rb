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

    def initialize(network, options, error_callback, init_diagnostics = nil)
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
        :experiment_to_layer => {}
      }

      @id_list_thread_pool = Concurrent::FixedThreadPool.new(
        options.idlist_threadpool_size,
        name: 'statsig-idlist',
        max_queue: 100,
        fallback_policy: :discard,
      )

      unless @options.bootstrap_values.nil?
        begin
          if !@options.data_store.nil?
            puts 'data_store gets priority over bootstrap_values. bootstrap_values will be ignored'
          else
            init_diagnostics&.mark("bootstrap", "start", "load")
            if process_specs(options.bootstrap_values)
              @init_reason = EvaluationReason::BOOTSTRAP
            end
            init_diagnostics&.mark("bootstrap", "end", "load", @init_reason == EvaluationReason::BOOTSTRAP)
          end
        rescue
          puts 'the provided bootstrapValues is not a valid JSON string'
        end
      end

      unless @options.data_store.nil?
        init_diagnostics&.mark("data_store", "start", "load")
        @options.data_store.init
        load_config_specs_from_storage_adapter(init_diagnostics: init_diagnostics)
        init_diagnostics&.mark("data_store", "end", "load", @init_reason == EvaluationReason::DATA_ADAPTER)
      end

      if @init_reason == EvaluationReason::UNINITIALIZED
        download_config_specs(init_diagnostics)
      end

      @initial_config_sync_time = @last_config_sync_time == 0 ? -1 : @last_config_sync_time
      if !@options.data_store.nil?
        get_id_lists_from_adapter(init_diagnostics)
      else
        get_id_lists_from_network(init_diagnostics)
      end

      @config_sync_thread = sync_config_specs
      @id_lists_sync_thread = sync_id_lists
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

    def get_raw_specs
      @specs
    end

    def maybe_restart_background_threads
      if @config_sync_thread.nil? or !@config_sync_thread.alive?
        @config_sync_thread = sync_config_specs
      end
      if @id_lists_sync_thread.nil? or !@id_lists_sync_thread.alive?
        @id_lists_sync_thread = sync_id_lists
      end
    end

    private

    def load_config_specs_from_storage_adapter(init_diagnostics: nil)
      init_diagnostics&.mark("download_config_specs", "start", "fetch_from_adapter")
      cached_values = @options.data_store.get(Interfaces::IDataStore::CONFIG_SPECS_KEY)
      init_diagnostics&.mark("download_config_specs", "end", "fetch_from_adapter", true)
      return if cached_values.nil?

      init_diagnostics&.mark("download_config_specs", "start", "process")
      process_specs(cached_values, from_adapter: true)
      @init_reason = EvaluationReason::DATA_ADAPTER
      init_diagnostics&.mark("download_config_specs", "end", "process", @init_reason)
    rescue StandardError
      # Fallback to network
      init_diagnostics&.mark("download_config_specs", "end", "fetch_from_adapter", false)
      download_config_specs(init_diagnostics)
    end

    def save_config_specs_to_storage_adapter(specs_string)
      if @options.data_store.nil?
        return
      end
      @options.data_store.set(Interfaces::IDataStore::CONFIG_SPECS_KEY, specs_string)
    end

    def sync_config_specs
      Thread.new do
        loop do
          sleep @options.rulesets_sync_interval
          if @options.data_store&.should_be_used_for_querying_updates(Interfaces::IDataStore::CONFIG_SPECS_KEY)
            load_config_specs_from_storage_adapter
          else
            download_config_specs
          end
        end
      end
    end

    def sync_id_lists
      Thread.new do
        loop do
          sleep @id_lists_sync_interval
          if @options.data_store&.should_be_used_for_querying_updates(Interfaces::IDataStore::ID_LISTS_KEY)
            get_id_lists_from_adapter
          else
            get_id_lists_from_network
          end
        end
      end
    end

    def download_config_specs(init_diagnostics = nil)
      init_diagnostics&.mark("download_config_specs", "start", "network_request")

      error = nil
      begin
        response, e = @network.post_helper('download_config_specs', JSON.generate({ 'sinceTime' => @last_config_sync_time }))
        code = response&.status.to_i
        if e.is_a? NetworkError
          code = e.http_code
        end
        init_diagnostics&.mark("download_config_specs", "end", "network_request", code)

        if e.nil?
          unless response.nil?
            init_diagnostics&.mark("download_config_specs", "start", "process")

            if process_specs(response.body.to_s)
              @init_reason = EvaluationReason::NETWORK
              @rules_updated_callback.call(response.body.to_s, @last_config_sync_time) unless response.body.nil? or @rules_updated_callback.nil?
            end

            init_diagnostics&.mark("download_config_specs", "end", "process", @init_reason == EvaluationReason::NETWORK)
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

      unless from_adapter
        save_config_specs_to_storage_adapter(specs_string)
      end
      true
    end

    def get_id_lists_from_adapter(init_diagnostics = nil)
      init_diagnostics&.mark("get_id_lists", "start", "fetch_from_adapter")
      cached_values = @options.data_store.get(Interfaces::IDataStore::ID_LISTS_KEY)
      return if cached_values.nil?

      init_diagnostics&.mark("get_id_lists", "end", "fetch_from_adapter", true)
      id_lists = JSON.parse(cached_values)
      process_id_lists(id_lists, init_diagnostics, from_adapter: true)
    rescue StandardError
      # Fallback to network
      init_diagnostics&.mark("get_id_lists", "end", "fetch_from_adapter", false)
      get_id_lists_from_network(init_diagnostics)
    end

    def save_id_lists_to_adapter(id_lists_raw_json)
      if @options.data_store.nil?
        return
      end
      @options.data_store.set(Interfaces::IDataStore::ID_LISTS_KEY, id_lists_raw_json)
    end

    def get_id_lists_from_network(init_diagnostics = nil)
      init_diagnostics&.mark("get_id_lists", "start", "network_request")
      response, e = @network.post_helper('get_id_lists', JSON.generate({ 'statsigMetadata' => Statsig.get_statsig_metadata }))
      if !e.nil? || response.nil?
        return
      end
      init_diagnostics&.mark("get_id_lists", "end", "network_request", response.status.to_i)

      begin
        server_id_lists = JSON.parse(response)
        process_id_lists(server_id_lists, init_diagnostics)
        save_id_lists_to_adapter(response.body.to_s)
      rescue
        # Ignored, will try again
      end
    end

    def process_id_lists(new_id_lists, init_diagnostics, from_adapter: false)
      local_id_lists = @specs[:id_lists]
      if !new_id_lists.is_a?(Hash) || !local_id_lists.is_a?(Hash)
        return
      end
      tasks = []

      if new_id_lists.length == 0
        return
      end

      init_diagnostics&.mark("get_id_lists", "start", "process", new_id_lists.length)

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
      init_diagnostics&.mark("get_id_lists", "end", "process", result.state == :fulfilled)
    end

    def get_single_id_list_from_adapter(list)
      cached_values = @options.data_store.get("#{Interfaces::IDataStore::ID_LISTS_KEY}::#{list.name}")
      content = cached_values.to_s
      process_single_id_list(list, content)
    rescue StandardError
      nil
    end

    def save_single_id_list_to_adapter(name, content)
      return if @options.data_store.nil?

      @options.data_store.set("#{Interfaces::IDataStore::ID_LISTS_KEY}::#{name}", content)
    end

    def download_single_id_list(list)
      nil unless list.is_a? IDList
      http = HTTP.headers({ 'Range' => "bytes=#{list&.size || 0}-" }).accept(:json)
      begin
        res = http.get(list.url)
        nil unless res.status.success?
        content_length = Integer(res['content-length'])
        nil if content_length.nil? || content_length <= 0
        content = res.body.to_s
        success = process_single_id_list(list, content, content_length)
        save_single_id_list_to_adapter(list.name, content) unless success.nil? || !success
      rescue
        nil
      end
    end

    def process_single_id_list(list, content, content_length = nil)
      false unless list.is_a? IDList
      begin
        unless content.is_a?(String) && (content[0] == '-' || content[0] == '+')
          @specs[:id_lists].delete(list.name)
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
        return true
      rescue
        return false
      end
    end
  end
end