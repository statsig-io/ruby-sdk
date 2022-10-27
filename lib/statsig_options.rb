# typed: true

require 'sorbet-runtime'
require_relative 'interfaces/data_store'

##
# Configuration options for the Statsig SDK.
class StatsigOptions
  extend T::Sig

  sig { returns(T.any(T::Hash[String, String], NilClass)) }
  # Hash you can use to set environment variables that apply to all of your users in
  # the same session and will be used for targeting purposes.
  # eg. { "tier" => "development" }
  attr_accessor :environment

  sig { returns(String) }
  # The base url used to make network calls to Statsig.
  # default: https://statsigapi.net/v1
  attr_accessor :api_url_base

  sig { returns(T.any(Float, Integer)) }
  # The interval (in seconds) to poll for changes to your Statsig configuration
  # default: 10s
  attr_accessor :rulesets_sync_interval

  sig { returns(T.any(Float, Integer)) }
  # The interval (in seconds) to poll for changes to your id lists
  # default: 60s
  attr_accessor :idlists_sync_interval

  sig { returns(T.any(Float, Integer)) }
  # How often to flush logs to Statsig
  # default: 60s
  attr_accessor :logging_interval_seconds

  sig { returns(Integer) }
  # The maximum number of events to batch before flushing logs to the server
  # default: 1000
  attr_accessor :logging_max_buffer_size

  sig { returns(T::Boolean) }
  # Restricts the SDK to not issue any network requests and only respond with default values (or local overrides)
  # default: false
  attr_accessor :local_mode

  sig { returns(T.any(String, NilClass)) }
  # A string that represents all rules for all feature gates, dynamic configs and experiments.
  # It can be provided to bootstrap the Statsig server SDK at initialization in case your server runs
  # into network issue or Statsig is down temporarily.
  attr_accessor :bootstrap_values

  sig { returns(T.any(Method, Proc, NilClass)) }
  # A callback function that will be called anytime the rulesets are updated.
  attr_accessor :rules_updated_callback

  sig { returns(T.any(Statsig::Interfaces::IDataStore, NilClass)) }
  # A class that extends IDataStore. Can be used to provide values from a
  # common data store (like Redis) to initialize the Statsig SDK.
  attr_accessor :data_store

  sig { returns(Integer) }
  # The number of threads allocated to syncing IDLists.
  # default: 3
  attr_accessor :idlist_threadpool_size

  sig do
    params(
      environment: T.any(T::Hash[String, String], NilClass),
      api_url_base: String,
      rulesets_sync_interval: T.any(Float, Integer),
      idlists_sync_interval: T.any(Float, Integer),
      logging_interval_seconds: T.any(Float, Integer),
      logging_max_buffer_size: Integer,
      local_mode: T::Boolean,
      bootstrap_values: T.any(String, NilClass),
      rules_updated_callback: T.any(Method, Proc, NilClass),
      data_store: T.any(Statsig::Interfaces::IDataStore, NilClass),
      idlist_threadpool_size: Integer
    ).void
  end

  def initialize(
    environment = nil,
    api_url_base = 'https://statsigapi.net/v1',
    rulesets_sync_interval: 10,
    idlists_sync_interval: 60,
    logging_interval_seconds: 60,
    logging_max_buffer_size: 1000,
    local_mode: false,
    bootstrap_values: nil,
    rules_updated_callback: nil,
    data_store: nil,
    idlist_threadpool_size: 3)
    @environment = environment.is_a?(Hash) ? environment : nil
    @api_url_base = api_url_base
    @rulesets_sync_interval = rulesets_sync_interval
    @idlists_sync_interval = idlists_sync_interval
    @logging_interval_seconds = logging_interval_seconds
    @logging_max_buffer_size = [logging_max_buffer_size, 1000].min
    @local_mode = local_mode
    @bootstrap_values = bootstrap_values
    @rules_updated_callback = rules_updated_callback
    @data_store = data_store
    @idlist_threadpool_size = idlist_threadpool_size
  end
end