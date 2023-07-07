# typed: true

require 'sorbet-runtime'

module Statsig
  class Diagnostics
    extend T::Sig

    sig { returns(String) }
    attr_reader :context

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_reader :markers

    def initialize(context)
      @context = context
      @markers = []
    end

    sig do
      params(
        key: String,
        action: String,
        step: T.any(String, NilClass),
        value: T.any(String, Integer, T::Boolean, NilClass),
        metadata: T.any(T::Hash[Symbol, T.untyped], NilClass)
      ).void
    end

    def mark(key, action, step = nil, value = nil, metadata = nil)
      @markers.push({
                      key: key,
                      step: step,
                      action: action,
                      value: value,
                      metadata: metadata,
                      timestamp: (Time.now.to_f * 1000).to_i
                    })
    end

    sig do
      params(
        key: String,
        step: T.any(String, NilClass),
        value: T.any(String, Integer, T::Boolean, NilClass),
        metadata: T.any(T::Hash[Symbol, T.untyped], NilClass)
      ).returns(Tracker)
    end
    def track(key, step = nil, value = nil, metadata = nil)
      tracker = Tracker.new(self, key, step, metadata)
      tracker.start(value)
      tracker
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }

    def serialize
      {
        context: @context.clone,
        markers: @markers.clone
      }
    end

    def clear_markers
      @markers.clear
    end

    def self.sample(rate)
      rand(rate).zero?
    end

    class Context
      INITIALIZE = 'initialize'.freeze
      CONFIG_SYNC = 'config_sync'.freeze
      API_CALL = 'api_call'.freeze
    end

    API_CALL_KEYS = %w[check_gate get_config get_experiment get_layer].freeze

    class Tracker
      extend T::Sig

      sig do
        params(
          diagnostics: Diagnostics,
          key: String,
          step: T.any(String, NilClass),
          metadata: T.any(T::Hash[Symbol, T.untyped], NilClass)
        ).void
      end
      def initialize(diagnostics, key, step, metadata)
        @diagnostics = diagnostics
        @key = key
        @step = step
        @metadata = metadata
      end

      def start(value = nil)
        @diagnostics.mark(@key, 'start', @step, value, @metadata)
      end

      def end(value = nil)
        @diagnostics.mark(@key, 'end', @step, value, @metadata)
      end
    end
  end
end
