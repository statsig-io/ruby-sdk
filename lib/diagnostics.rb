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

    sig { returns(T::Hash[Symbol, T.untyped]) }

    def serialize
      {
        context: @context,
        markers: @markers
      }
    end
  end

end