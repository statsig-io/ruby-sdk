require 'net/http'
require 'uri'

require 'id_list'

module Statsig
  class SpecStore
    def initialize(network, error_callback = nil, config_sync_interval = 10, id_lists_sync_interval = 60)
      @network = network
      @last_sync_time = 0
      @config_sync_interval = config_sync_interval
      @id_lists_sync_interval = id_lists_sync_interval
      @store = {
        :gates => {},
        :configs => {},
        :layers => {},
        :id_lists => {},
      }
      e = download_config_specs
      error_callback.call(e) unless error_callback.nil?
      get_id_lists

      @config_sync_thread = sync_config_specs
      @id_lists_sync_thread = sync_id_lists
    end

    def shutdown
      @config_sync_thread&.exit
      @id_lists_sync_thread&.exit
    end

    def has_gate?(gate_name)
      @store[:gates].key?(gate_name)
    end

    def has_config?(config_name)
      @store[:configs].key?(config_name)
    end

    def has_layer?(layer_name)
      @store[:layers].key?(layer_name)
    end

    def get_gate(gate_name)
      return nil unless has_gate?(gate_name)
      @store[:gates][gate_name]
    end

    def get_config(config_name)
      return nil unless has_config?(config_name)
      @store[:configs][config_name]
    end

    def get_layer(layer_name)
      return nil unless has_layer?(layer_name)
      @store[:layers][layer_name]
    end

    def get_id_list(list_name)
      @store[:id_lists][list_name]
    end

    private

    def sync_config_specs
      Thread.new do
        loop do
          sleep @config_sync_interval
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
      begin
        response, e = @network.post_helper('download_config_specs', JSON.generate({'sinceTime' => @last_sync_time}))
        if e.nil?
          process(JSON.parse(response.body))
        else
          e
        end
      rescue StandardError => e
        e
      end
    end

    def process(specs_json)
      if specs_json.nil?
        return
      end

      @last_sync_time = specs_json['time'] || @last_sync_time
      return unless specs_json['has_updates'] == true &&
        !specs_json['feature_gates'].nil? &&
        !specs_json['dynamic_configs'].nil? &&
        !specs_json['layer_configs'].nil? 

      new_gates = {}
      new_configs = {}
      new_layers = {}

      specs_json['feature_gates'].map{|gate|  new_gates[gate['name']] = gate }
      specs_json['dynamic_configs'].map{|config|  new_configs[config['name']] = config }
      specs_json['layer_configs'].map{|layer|  new_layers[layer['name']] = layer }
      @store[:gates] = new_gates
      @store[:configs] = new_configs
      @store[:layers] = new_layers
    end

    def get_id_lists
      response, e = @network.post_helper('get_id_lists', JSON.generate({'statsigMetadata' => Statsig.get_statsig_metadata}))
      if !e.nil? || response.nil?
        return
      end

      begin
        server_id_lists = JSON.parse(response)
        local_id_lists = @store[:id_lists]
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

          # skip if server list returns a newer file
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
      http = HTTP.headers({'Range' => "bytes=#{list&.size || 0}-"}).accept(:json)
      begin
        res = http.get(list.url)
        nil unless res.status.success?
        content_length = Integer(res['content-length'])
        nil if content_length.nil? || content_length <= 0
        content = res.body.to_s
        unless content.is_a?(String) && (content[0] == '-' || content[0] == '+')
          @store[:id_lists].delete(list.name)
          return
        end
        ids_clone = list.ids # clone the list, operate on the new list, and swap out the old list, so the operation is thread-safe
        lines = content.split(/\r?\n/)
        lines.each do |li|
          line = li.strip
          next if line.length <= 1
          op = line[0]
          id = line[1..]
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