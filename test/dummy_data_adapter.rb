

require 'interfaces/data_store'

class DummyDataAdapter < Statsig::Interfaces::IDataStore
  attr_accessor :store, :poll_config_specs

  def initialize(poll_config_specs: false, poll_id_lists: false)
    @poll_config_specs = poll_config_specs
    @poll_id_lists = poll_id_lists
  end

  def init
    @store = {
      'statsig.cache' => "<BadJson - DcsV1 should no longer be hit>",
      Statsig::Interfaces::IDataStore::CONFIG_SPECS_V2_KEY => '{
        "feature_gates": {
          "gate_from_adapter": {
            "name": "gate_from_adapter",
            "type": "feature_gate",
            "salt": "47403b4e-7829-43d1-b1ac-3992a5c1b4ac",
            "enabled": true,
            "defaultValue": false,
            "rules": [
              {
                "name": "6N6Z8ODekNYZ7F8gFdoLP5",
                "groupName": "everyone",
                "passPercentage": 100,
                "conditions": [
                  "2950400045"
                ],
                "returnValue": true,
                "id": "6N6Z8ODekNYZ7F8gFdoLP5",
                "salt": "14862979-1468-4e49-9b2a-c8bb100eed8f"
              }
            ],
            "idType": "userID"
          },
          "test_id_list": {
            "name": "test_id_list",
            "type": "feature_gate",
            "salt": "7113c807-8236-477f-ac1c-bb8ac69bc9f7",
            "enabled": true,
            "defaultValue": false,
            "rules": [
              {
                "name": "1WF7SXC60cUGiiLvutKKQO",
                "groupName": "id_list",
                "passPercentage": 100,
                "conditions": [
                  "366651914"
                ],
                "returnValue": true,
                "id": "1WF7SXC60cUGiiLvutKKQO",
                "salt": "61ac4901-051f-4448-ae0e-f559cc55294e",
                "isDeviceBased": false,
                "idType": "userID"
              }
            ],
            "isDeviceBased": false,
            "idType": "userID",
            "entity": "feature_gate"
          },
          "segment:user_id_list": {
            "name": "segment:user_id_list",
            "type": "feature_gate",
            "salt": "2b81f86d-abd5-444f-93f4-79edf1815cd2",
            "enabled": true,
            "defaultValue": false,
            "rules": [
              {
                "name": "id_list",
                "groupName": "id_list",
                "passPercentage": 100,
                "conditions": [
                  "442395722"
                ],
                "returnValue": true,
                "id": "id_list",
                "salt": "",
                "isDeviceBased": false,
                "idType": "userID"
              }
            ],
            "isDeviceBased": false,
            "idType": "userID",
            "entity": "segment"
          }
        },
        "dynamic_configs": {},
        "layer_configs": {},
        "has_updates": true,
        "time": 1,
        "condition_map": {
          "366651914": {
            "type": "pass_gate",
            "targetValue": "segment:user_id_list",
            "operator": null,
            "field": null,
            "additionalValues": {},
            "isDeviceBased": false,
            "idType": "userID"
          },
          "442395722": {
            "type": "unit_id",
            "targetValue": "user_id_list",
            "operator": "in_segment_list",
            "additionalValues": {},
            "isDeviceBased": false,
            "idType": "userID"
          },
          "2950400045": {
            "type": "public"
          }
        },
        "experiment_to_layer": {}
      }',
      Statsig::Interfaces::IDataStore::ID_LISTS_KEY => {
        "user_id_list" => {
          "name" => "user_id_list",
          "size" => "+Z/hEKLio\n+M5m6a10x\n".bytesize,
          "url" => "https://idliststorage.fake",
          "creationTime" => 1,
          "fileID" => "123"
        }
      }.to_json,
      "#{Statsig::Interfaces::IDataStore::ID_LISTS_KEY}::user_id_list" => "+Z/hEKLio\n+M5m6a10x\n"
    }
  end

  def get(key)
    return nil unless @store&.key?(key)

    @store[key]
  end

  def set(key, value)
    @store[key] = value
  end

  def shutdown
    @store = {}
  end

  def should_be_used_for_querying_updates(key)
    return @poll_config_specs if key == Statsig::Interfaces::IDataStore::CONFIG_SPECS_V2_KEY
    return @poll_id_lists if key == Statsig::Interfaces::IDataStore::ID_LISTS_KEY

    false
  end

  def remove_feature_gate(gate_name)
    specs = JSON.parse(get(Statsig::Interfaces::IDataStore::CONFIG_SPECS_V2_KEY))
    specs["feature_gates"].delete(gate_name)
    set(Statsig::Interfaces::IDataStore::CONFIG_SPECS_V2_KEY, JSON.generate(specs))
  end

  def update_id_lists
    new_id_list = "+Z/hEKLio\n+M5m6a10x\n+uXWuayti\n-Z/hEKLio\n-M5m6a10x\n"
    set(Statsig::Interfaces::IDataStore::ID_LISTS_KEY, {
      "user_id_list" => {
        "name" => "user_id_list",
        "size" => new_id_list.bytesize,
        "url" => "https://idliststorage.fake",
        "creationTime" => 1,
        "fileID" => "123"
      }
    }.to_json)
    set("#{Statsig::Interfaces::IDataStore::ID_LISTS_KEY}::user_id_list", new_id_list)
  end

  def corrupt_store
    @store = { Statsig::Interfaces::IDataStore::CONFIG_SPECS_V2_KEY => 'corrupted', Statsig::Interfaces::IDataStore::ID_LISTS_KEY => 'corrupted' }
  end

  def clear_store
    @store = {
      Statsig::Interfaces::IDataStore::CONFIG_SPECS_V2_KEY => {
        'feature_gates' => {},
        'dynamic_configs' => {},
        'layer_configs' => {},
        'condition_map' => {},
        'has_updates' => true,
        'time' => 1
      }.to_json
    }
  end
end
