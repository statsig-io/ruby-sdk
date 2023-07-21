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

    def self.sha256(input_str)
      return Digest::SHA256.base64digest(input_str)
    end
  end
end
