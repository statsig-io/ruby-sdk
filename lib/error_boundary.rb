# typed: true

require 'statsig_errors'
require 'sorbet-runtime'

$endpoint = 'https://statsigapi.net/v1/sdk_exception'

module Statsig
  class ErrorBoundary
    extend T::Sig

    sig { returns(T.any(StatsigLogger, NilClass)) }
    attr_accessor :logger

    sig { params(sdk_key: String).void }
    def initialize(sdk_key)
      @sdk_key = sdk_key
      @seen = Set.new
    end

    def sample_diagnostics
      rand(10_000).zero?
    end

    def capture(task:, recover: -> {}, caller: nil)
      if !caller.nil? && Diagnostics::API_CALL_KEYS.include?(caller) && sample_diagnostics
        diagnostics = Diagnostics.new('api_call')
        tracker = diagnostics.track(caller)
      end
      begin
        res = task.call
        tracker&.end(true)
      rescue StandardError => e
        tracker&.end(false)
        if e.is_a?(Statsig::UninitializedError) or e.is_a?(Statsig::ValueError)
          raise e
        end
        puts '[Statsig]: An unexpected exception occurred.'
        log_exception(e)
        res = recover.call
      end
      @logger&.log_diagnostics_event(diagnostics)
      return res
    end

    private

    def log_exception(exception)
      begin
        name = exception.class.name
        if @seen.include?(name)
          return
        end

        @seen << name
        meta = Statsig.get_statsig_metadata
        http = HTTP.headers(
          {
            'STATSIG-API-KEY' => @sdk_key,
            'STATSIG-SDK-TYPE' => meta['sdkType'],
            'STATSIG-SDK-VERSION' => meta['sdkVersion'],
            'Content-Type' => 'application/json; charset=UTF-8'
          }).accept(:json)
        body = {
          'exception' => name,
          'info' => {
            'trace' => exception.backtrace.to_s,
            'message' => exception.message
          }.to_s,
          'statsigMetadata' => meta
        }
        http.post($endpoint, body: JSON.generate(body))
      rescue
        return
      end
    end
  end
end