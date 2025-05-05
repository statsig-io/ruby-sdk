require 'json'
require 'digest'

TWO_TO_THE_63 = 1 << 63
TWO_TO_THE_64 = 1 << 64
module Statsig
  class HashUtils
    def self.djb2(input_str)
      hash = 0
      input_str.each_char.each do |c|
        hash = (hash << 5) - hash + c.ord
        hash &= 0xFFFFFFFF
      end
      hash &= 0xFFFFFFFF # Convert to unsigned 32-bit integer
      return hash.to_s
    end

    def self.djb2ForHash(input_hash)
      return djb2(input_hash.to_json)
    end

    def self.sha256(input_str)
      return Digest::SHA256.base64digest(input_str)
    end

    def self.md5(input_str)
      return Digest::MD5.base64digest(input_str)
    end

    def self.sortHash(input_hash)
      dictionary = input_hash.clone.sort_by { |key| key }.to_h;
      input_hash.each do |key, value|
        if value.is_a?(Hash)
          dictionary[key] = self.sortHash(value)
        end
      end
      return dictionary
    end

    def self.bigquery_hash(string)
      digest = Digest::SHA256.digest(string)
      num = digest[0...8].unpack('Q>')[0]
      
      if num >= TWO_TO_THE_63
        num - TWO_TO_THE_64
      else
        num
      end
    end

    def self.is_hash_in_sampling_rate(key, sampling_rate)
      hash_key = bigquery_hash(key)
      hash_key % sampling_rate == 0
    end

    def self.compute_dedupe_key_for_gate(gate_name, rule_id, value, user_id, custom_ids = nil)
      user_key = compute_user_key(user_id, custom_ids)
      "n:#{gate_name};u:#{user_key}r:#{rule_id};v:#{value}"
    end

    def self.compute_dedupe_key_for_config(config_name, rule_id, user_id, custom_ids = nil)
      user_key = compute_user_key(user_id, custom_ids)
      "n:#{config_name};u:#{user_key}r:#{rule_id}"
    end

    def self.compute_dedupe_key_for_layer(layer_name, experiment_name, parameter_name, rule_id, user_id, custom_ids = nil)
      user_key = compute_user_key(user_id, custom_ids)
      "n:#{layer_name};e:#{experiment_name};p:#{parameter_name};u:#{user_key}r:#{rule_id}"
    end

    def self.compute_user_key(user_id, custom_ids = nil)
      user_key = "u:#{user_id};"
      if custom_ids
        custom_ids.each do |k, v|
          user_key += "#{k}:#{v};"
        end
      end
      user_key
    end
  end
end
