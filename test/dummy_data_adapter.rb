# typed: true
require 'interfaces/data_store'

class DummyDataAdapter < Statsig::Interfaces::IDataStore
  attr_accessor :store
  attr_accessor :poll_config_specs

  def initialize(poll_config_specs: false)
    @poll_config_specs = poll_config_specs
  end

  def init
    @store = {
      'statsig.cache' => {
        'feature_gates' => [{
            'name' => 'gate_from_adapter',
            'type' => 'feature_gate',
            'salt' => '47403b4e-7829-43d1-b1ac-3992a5c1b4ac',
            'enabled' => true,
            'defaultValue' => false,
            'rules' => [{
              'name' => '6N6Z8ODekNYZ7F8gFdoLP5',
              'groupName' => 'everyone',
              'passPercentage' => 100,
              'conditions' => [{'type' => 'public', }],
              'returnValue' => true,
              'id' => '6N6Z8ODekNYZ7F8gFdoLP5',
              'salt' => '14862979-1468-4e49-9b2a-c8bb100eed8f'
            }]
        }],
        'dynamic_configs' => [],
        'layer_configs' => [],
        'has_updates' => true,
        'last_update_time' => 1,
      }.to_json
    }
  end

  def get(key)
    return nil unless @store.key?(key)
    @store[key]
  end

  def set(key, value)
    @store[key] = value
  end

  def shutdown
    @store = {}
  end

  def should_be_used_for_polling(key)
    if key == Statsig::Interfaces::IDataStore::CONFIG_SPECS_KEY
      return @poll_config_specs
    end
    return false
  end

  def clear_store
    @store = {
      'statsig.cache' => {
        'feature_gates' => [],
        'dynamic_configs' => [],
        'layer_configs' => [],
        'has_updates' => true,
        'last_update_time' => 1,
      }.to_json
    }
  end
end