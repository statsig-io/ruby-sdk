require 'concurrent-ruby'

RESET_INTERVAL = 60

module Statsig
  class TTLSet
    def initialize
      @store = Concurrent::Set.new
      @reset_interval = RESET_INTERVAL
      @background_reset = periodic_reset
    end

    def add(key)
      @store.add(key)
    end

    def contains?(key)
      @store.include?(key)
    end

    def shutdown
      @background_reset&.exit
    end

    def periodic_reset
      Thread.new do
        loop do
          sleep @reset_interval
          @store.clear
        end
      end
    end
  end
end


