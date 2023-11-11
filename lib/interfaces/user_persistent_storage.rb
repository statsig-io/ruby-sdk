# typed: true
module Statsig
  module Interfaces
    class IUserPersistentStorage
      def load(key)
        nil
      end

      def save(key, data) end
    end
  end
end
