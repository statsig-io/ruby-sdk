module Statsig
  class Diagnostics
    attr_reader :markers

    attr_accessor :sample_rates

    def initialize()
      @markers = {:initialize => [], :api_call => [], :config_sync => []}
      @sample_rates = {}
    end

    def mark(key, action, step, tags, context)
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
      if @markers[context].nil?
        @markers[context] = []
      end
      @markers[context].push(marker)
    end

    def track(context, key, step = nil, tags = {})
      tracker = Tracker.new(self, context, key, step, tags)
      tracker.start(**tags)
      tracker
    end

    def serialize_with_sampling(context)
      marker_keys = @markers[context].map { |e| e[:key] }
      unique_marker_keys = marker_keys.uniq { |e| e }
      sampled_marker_keys = unique_marker_keys.select do |key|
        @sample_rates.key?(key) && !self.class.sample(@sample_rates[key])
      end
      final_markers = @markers[context].select do |marker|
        !sampled_marker_keys.include?(marker[:key])
      end
      {
        context: context.clone,
        markers: final_markers.clone
      }
    end

    def clear_markers(context)
      @markers[context].clear
    end

    def self.sample(rate_over_ten_thousand)
      rand * 10_000 < rate_over_ten_thousand
    end

    API_CALL_KEYS = {
      :check_gate => true,
      :get_config => true,
      :get_experiment => true,
      :get_layer => true
    }.freeze

    class Tracker
      def initialize(diagnostics, context, key, step, tags = {})
        @diagnostics = diagnostics
        @context = context
        @key = key
        @step = step
        @tags = tags
      end

      def start(**tags)
        @diagnostics.mark(@key, 'start', @step, tags.nil? ? {} : tags.merge(@tags), @context)
      end

      def end(**tags)
        @diagnostics.mark(@key, 'end', @step, tags.nil? ? {} : tags.merge(@tags), @context)
      end
    end
  end
end