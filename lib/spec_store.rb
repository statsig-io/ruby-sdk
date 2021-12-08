require 'net/http'
require 'uri'

class SpecStore
  def initialize(network, error_callback)
    @network = network
    @last_sync_time = 0
    @store = {
      :gates => {},
      :configs => {},
      :id_lists => {},
    }
    e = download_config_specs
    error_callback.call(e) unless error_callback.nil?

    @config_sync_thread = sync_config_specs
  end

  def shut_down
    @config_sync_thread&.exit
  end

  def has_gate?(gate_name)
    @store[:gates].key?(gate_name)
  end

  def has_config?(config_name)
    @store[:configs].key?(config_name)
  end

  def get_gate(gate_name)
    return nil unless has_gate?(gate_name)
    @store[:gates][gate_name]
  end

  def get_config(config_name)
    return nil unless has_config?(config_name)
    @store[:configs][config_name]
  end

  private

  def sync_config_specs
    Thread.new do
      loop do
        sleep 10
        download_config_specs
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
      !specs_json['dynamic_configs'].nil?

    new_gates = {}
    new_configs = {}

    specs_json['feature_gates'].map{|gate|  new_gates[gate['name']] = gate }
    specs_json['dynamic_configs'].map{|config|  new_configs[config['name']] = config }
    @store[:gates] = new_gates
    @store[:configs] = new_configs

    new_id_lists = specs_json['id_lists']
    if new_id_lists.is_a? Hash
      new_id_lists.each do |list_name, _|
        unless @store[:id_lists].key?(list_name)
          @store[:id_lists][list_name] = { ids: {}, time: 0 }
        end
      end

      @store[:id_lists].each do |list_name, _|
        unless new_id_lists.key?(list_name)
          @store[:id_lists].delete(list_name)
        end
      end
    end
  end

end
