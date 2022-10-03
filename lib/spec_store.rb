require 'net/http'
require 'uri'
require 'evaluation_details'
require 'id_list'

module Statsig
  class SpecStore

    CONFIG_SPECS_KEY = "statsig.cache"

    attr_accessor :last_config_sync_time
    attr_accessor :initial_config_sync_time
    attr_accessor :init_reason

    def initialize(network, options, error_callback)
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

      unless @options.bootstrap_values.nil?
        begin
          if !@options.data_store.nil?
            puts 'data_store gets priority over bootstrap_values. bootstrap_values will be ignored'
          elsif process(options.bootstrap_values)
            @init_reason = EvaluationReason::BOOTSTRAP
          end
        rescue
          puts 'the provided bootstrapValues is not a valid JSON string'
        end
      end

      unless @options.data_store.nil?
        @options.data_store.init
        load_from_storage_adapter
      end

      download_config_specs
      @initial_config_sync_time = @last_config_sync_time == 0 ? -1 : @last_config_sync_time
      get_id_lists

      @config_sync_thread = sync_config_specs
      @id_lists_sync_thread = sync_id_lists
    end

    def is_ready_for_checks
      @last_config_sync_time != 0
    end

    def shutdown
      @config_sync_thread&.exit
      @id_lists_sync_thread&.exit
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

    def load_from_storage_adapter
      cached_values = @options.data_store.get(CONFIG_SPECS_KEY)
      if cached_values.nil?
        return
      end
      process(cached_values, true)
      @init_reason = EvaluationReason::DATA_ADAPTER
    end

    def save_to_storage_adapter(specs_string)
      if @options.data_store.nil?
        return
      end
      @options.data_store.set(CONFIG_SPECS_KEY, specs_string)
    end

    def sync_config_specs
      Thread.new do
        loop do
          sleep @options.rulesets_sync_interval
          download_config_specs
        end
      end
    end

    def sync_id_lists
      Thread.new do
        loop do
          sleep @id_lists_sync_interval
          get_id_lists
        end
      end
    end

    def download_config_specs
      e = get_config_specs_from_network
      @error_callback.call(e) unless e.nil? or @error_callback.nil?
    end

    def get_config_specs_from_network
      begin
        response, e = @network.post_helper('download_config_specs', JSON.generate({ 'sinceTime' => @last_config_sync_time }))
        if e.nil?
          if process(response.body)
            @init_reason = EvaluationReason::NETWORK
            @rules_updated_callback.call(response.body.to_s, @last_config_sync_time) unless response.body.nil? or @rules_updated_callback.nil?
          end
          nil
        else
          e
        end
      rescue StandardError => e
        e
      end
    end

    def process(specs_string, from_adapter = false)
      if specs_string.nil?
        return false
      end
      specs_json = JSON.parse(specs_string)
      if specs_string.nil?
        return false
      end

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
        save_to_storage_adapter(specs_string)
      end
      true
    end

    def get_id_lists
      response, e = @network.post_helper('get_id_lists', JSON.generate({ 'statsigMetadata' => Statsig.get_statsig_metadata }))
      if !e.nil? || response.nil?
        return
      end

      begin
        server_id_lists = JSON.parse(response)
        local_id_lists = @specs[:id_lists]
        if !server_id_lists.is_a?(Hash) || !local_id_lists.is_a?(Hash)
          return
        end
        threads = []

        server_id_lists.each do |list_name, list|
          server_list = IDList.new(list)
          local_list = get_id_list(list_name)

          unless local_list.is_a? IDList
            local_list = IDList.new(list)
            local_list.size = 0
            local_id_lists[list_name] = local_list
          end

          # skip if server list is invalid
          if server_list.url.nil? || server_list.creation_time < local_list.creation_time || server_list.file_id.nil?
            next
          end

          # reset local list if server list returns a newer file
          if server_list.file_id != local_list.file_id && server_list.creation_time >= local_list.creation_time
            local_list = IDList.new(list)
            local_list.size = 0
            local_id_lists[list_name] = local_list
          end

          # skip if server list is no bigger than local list, which means nothing new to read
          if server_list.size <= local_list.size
            next
          end

          threads << Thread.new do
            download_single_id_list(local_list)
          end
        end
        threads.each(&:join)
        delete_lists = []
        local_id_lists.each do |list_name, list|
          unless server_id_lists.key? list_name
            delete_lists.push list_name
          end
        end
        delete_lists.each do |list_name|
          local_id_lists.delete list_name
        end
      rescue
        # Ignored, will try again
      end
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
        unless content.is_a?(String) && (content[0] == '-' || content[0] == '+')
          @specs[:id_lists].delete(list.name)
          return
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
        list.size = list.size + content_length
      rescue
        nil
      end
    end
  end
end