module Statsig
  module Interfaces
    class IDataStore
      def init
      end

      def get(key)
        nil
      end

      def set(key, value)
      end

      def shutdown
      end
    end
  end
end