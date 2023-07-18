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
        tags: T::Hash[Symbol, T.untyped]
      ).void
    end

    def mark(key, action, step, tags)
      marker = {
        key: key,
        action: action,
        timestamp: (Time.now.to_f * 1000).to_i
      }
      if !step.nil?
        marker[:step] = step
      end
      tags.each do |key, val|
        unless val.nil?
          marker[key] = val
        end
      end
      @markers.push(marker)
    end

    sig do
      params(
        key: String,
        step: T.any(String, NilClass),
        tags: T::Hash[Symbol, T.untyped]
      ).returns(Tracker)
    end
    def track(key, step = nil, tags = {})
      tracker = Tracker.new(self, key, step, tags)
      tracker.start(**tags)
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
          tags: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(diagnostics, key, step, tags = {})
        @diagnostics = diagnostics
        @key = key
        @step = step
        @tags = tags
      end

      def start(**tags)
        @diagnostics.mark(@key, 'start', @step, tags.nil? ? {} : tags.merge(@tags))
      end

      def end(**tags)
        @diagnostics.mark(@key, 'end', @step, tags.nil? ? {} : tags.merge(@tags))
      end
    end
  end
end
