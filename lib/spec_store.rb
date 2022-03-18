require 'net/http'
require 'uri'

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
      download_id_lists

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
          download_id_lists
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

      new_id_lists = specs_json['id_lists']
      if new_id_lists.is_a? Hash
        new_id_lists.each do |list_name, _|
          unless @store[:id_lists].key?(list_name)
            @store[:id_lists][list_name] = { :ids => {}, :time => 0 }
          end
        end

        @store[:id_lists].each do |list_name, _|
          unless new_id_lists.key?(list_name)
            @store[:id_lists].delete(list_name)
          end
        end
      end
    end

    def download_id_lists
      if @store[:id_lists].is_a? Hash
        threads = []
        id_lists = @store[:id_lists]
        id_lists.each do |list_name, list|
          threads << Thread.new do
            response, e = @network.post_helper('download_id_list', JSON.generate({'listName' => list_name, 'statsigMetadata' => Statsig.get_statsig_metadata, 'sinceTime' => list['time'] || 0 }))
            if e.nil? && !response.nil?
              begin
                data = JSON.parse(response)
                if data['add_ids'].is_a? Array
                  data['add_ids'].each do |id|
                    list[:ids][id] = true
                  end
                end
                if data['remove_ids'].is_a? Array
                  data['remove_ids'].each do |id|
                    list[:ids]&.delete(id)
                  end
                end
                if data['time'].is_a? Numeric
                  list[:time] = data['time']
                end
              rescue
                # Ignored
              end
            end
          end
        end
        threads.each(&:join)
      end
    end
  end
end