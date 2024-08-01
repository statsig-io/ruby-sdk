
module Statsig
  module Interfaces
    class IDataStore
      CONFIG_SPECS_V2_KEY = "statsig.dcs_v2"
      ID_LISTS_KEY = "statsig.id_lists"

      def init
      end

      def get(key)
        nil
      end

      def set(key, value)
      end

      def shutdown
      end

      ##
      # Determines whether the SDK should poll for updates from
      # the data adapter (instead of Statsig network) for the given key
      #
      # @param key Key of stored item to poll from data adapter
      def should_be_used_for_querying_updates(key)
      end
    end
  end
end