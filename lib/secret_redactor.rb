require 'json'
require 'uri'

module Statsig
  # Sanitizes SDK-generated output without changing outgoing requests.
  class SecretRedactor
    def initialize(secret)
      @secret = secret.to_s
    end

    def text(value)
      result = value.to_s.dup
      unless @secret.empty?
        variants = [@secret, URI.encode_www_form_component(@secret), URI::DEFAULT_PARSER.escape(@secret)]
        variants += variants.map { |v| JSON.generate(v)[1...-1] }
        variants.uniq.sort_by { |v| -v.length }.each { |v| result.gsub!(v, '[REDACTED]') unless v.empty? }
      end
      result.gsub!(%r{(/download_config_specs/)[^/?\s"']+}i) do
        segment = Regexp.last_match(0)
        "#{Regexp.last_match(1)}[REDACTED]#{segment.end_with?('.json') ? '.json' : ''}"
      end
      result
    end

    # Build a fresh exception without retaining the original cause or fields.
    # Its class is preserved when Ruby allows allocation, preserving classification.
    def exception(error)
      copy = error.class.allocate
      Exception.instance_method(:initialize).bind(copy).call(text(error.message))
      copy.set_backtrace(error.backtrace.map { |line| text(line) }) if error.backtrace
      copy
    rescue StandardError, TypeError
      safe = StandardError.new(text(error.message))
      safe.set_backtrace(error.backtrace.map { |line| text(line) }) if error.backtrace
      safe
    end
  end
end
