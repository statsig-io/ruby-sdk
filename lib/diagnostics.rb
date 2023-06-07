# typed: true

require 'sorbet-runtime'

module Statsig
  class Diagnostics
    extend T::Sig

    sig { returns(String) }
    attr_reader :context

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_reader :markers

    sig { params(context: String).void }

    def initialize(context)
      @context = context
      @markers = []
    end

    sig { params(key: String, action: String, step: T.any(String, NilClass), value: T.any(String, Integer, T::Boolean, NilClass)).void }

    def mark(key, action, step = nil, value = nil)
      @markers.push({
                      key: key,
                      step: step,
                      action: action,
                      value: value,
                      timestamp: (Time.now.to_f * 1000).to_i
                    })
    end

    sig { params(key: String, step: T.any(String, NilClass), value: T.any(String, Integer, T::Boolean, NilClass)).returns(Tracker) }
    def track(key, step = nil, value = nil)
      tracker = Tracker.new(self, key, step)
      tracker.start(value)
      tracker
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }

    def serialize
      {
        context: @context,
        markers: @markers
      }
    end

    class Tracker
      extend T::Sig

      sig { params(diagnostics: Diagnostics, key: String, step: T.any(String, NilClass)).void }
      def initialize(diagnostics, key, step)
        @diagnostics = diagnostics
        @key = key
        @step = step
      end

      def start(value = nil)
        @diagnostics.mark(@key, 'start', @step, value)
      end

      def end(value = nil)
        @diagnostics.mark(@key, 'end', @step, value)
      end
    end
  end
end
