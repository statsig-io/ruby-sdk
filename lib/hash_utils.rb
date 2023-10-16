require 'json'
module Statsig
  class HashUtils
    def self.djb2(input_str)
      hash = 0
      input_str.each_char.each do |c|
        hash = (hash << 5) - hash + c.ord
        hash &= hash
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

    def self.sortHash(input_hash)
      dictionary = input_hash.clone.sort_by { |key| key }.to_h;
      input_hash.each do |key, value|
        if value.is_a?(Hash)
          dictionary[key] = self.sortHash(value)
        end
      end
      return dictionary
    end
  end
end
