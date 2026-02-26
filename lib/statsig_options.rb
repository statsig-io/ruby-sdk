require_relative 'interfaces/data_store'
require_relative 'interfaces/user_persistent_storage'

##
# Configuration options for the Statsig SDK.
class StatsigOptions

  # A string that represents all rules for all feature gates, dynamic configs and experiments.
  # It can be provided to bootstrap the Statsig server SDK at initialization in case your server runs
  # into network issue or Statsig is down temporarily.
  attr_accessor :bootstrap_values

  # A class that extends IDataStore. Can be used to provide values from a
  # common data store (like Redis) to initialize the Statsig SDK.
  attr_accessor :data_store

  # Should diagnostics be logged. These include performance metrics for initialize.
  # default: false
  attr_accessor :disable_diagnostics_logging

  # Disable memoization of evaluation results. When true, each evaluation will be performed fresh.
  # default: false
  attr_accessor :disable_evaluation_memoization

  # Disable background syncing for id lists
  attr_accessor :disable_idlists_sync

  # Disable background syncing for rulesets
  attr_accessor :disable_rulesets_sync

  # Statsig utilizes Sorbet (https://sorbet.org) to ensure type safety of the SDK. This includes logging
  # to console when errors are detected. You can disable this logging by setting this flag to true.
  # default: false
  attr_accessor :disable_sorbet_logging_handlers

  # The url used specifically to call download_config_specs.
  attr_accessor :download_config_specs_url

  # Hash you can use to set environment variables that apply to all of your users in
  # the same session and will be used for targeting purposes.
  # eg. { "tier" => "development" }
  attr_accessor :environment

  # The url used specifically to call get_id_lists.
  attr_accessor :get_id_lists_url

  # The number of threads allocated to syncing IDLists.
  # default: 3
  attr_accessor :idlist_threadpool_size

  # The interval (in seconds) to poll for changes to your id lists
  # default: 60s
  attr_accessor :idlists_sync_interval

  # Restricts the SDK to not issue any network requests and only respond with default values (or local overrides)
  # default: false
  attr_accessor :local_mode

  # The url used specifically to call log_event.
  attr_accessor :log_event_url

  # The number of threads allocated to posting event logs.
  # default: 3
  attr_accessor :logger_threadpool_size

  # How often to flush logs to Statsig
  # default: 60s
  attr_accessor :logging_interval_seconds

  # The maximum number of events to batch before flushing logs to the server
  # default: 1000
  attr_accessor :logging_max_buffer_size

  # Number of seconds before a network call is timed out
  # default: 30s
  attr_accessor :network_timeout

  # The number of seconds, or a function that returns the number of seconds based on the number of retries remaining
  # which overrides the default backoff time between retries
  attr_accessor :post_logs_retry_backoff

  # Number of times to retry sending a batch of failed log events
  attr_accessor :post_logs_retry_limit

  # A callback function that will be called anytime the rulesets are updated.
  attr_accessor :rules_updated_callback

  # Number of times to retry fetching rulesets and id lists
  # default: 3
  attr_accessor :ruleset_id_list_retry_limit

  # The interval (in seconds) to poll for changes to your Statsig configuration
  # default: 10s
  attr_accessor :rulesets_sync_interval

  # A storage adapter for persisted values. Can be used for sticky bucketing users in experiments.
  # Implements Statsig::Interfaces::IUserPersistentStorage.
  attr_accessor :user_persistent_storage

  def initialize(
    bootstrap_values: nil,
    data_store: nil,
    disable_diagnostics_logging: false,
    disable_evaluation_memoization: false,
    disable_idlists_sync: false,
    disable_rulesets_sync: false,
    disable_sorbet_logging_handlers: false,
    download_config_specs_url: nil,
    environment: nil,
    get_id_lists_url: nil,
    idlist_threadpool_size: 3,
    idlists_sync_interval: 60,
    local_mode: false,
    log_event_url: nil,
    logger_threadpool_size: 3,
    logging_interval_seconds: 60,
    logging_max_buffer_size: 1000,
    network_timeout: 30,
    post_logs_retry_backoff: nil,
    post_logs_retry_limit: 3,
    rules_updated_callback: nil,
    ruleset_id_list_retry_limit: 3,
    rulesets_sync_interval: 10,
    user_persistent_storage: nil
  )
    @bootstrap_values = bootstrap_values
    @data_store = data_store
    @disable_diagnostics_logging = disable_diagnostics_logging
    @disable_evaluation_memoization = disable_evaluation_memoization
    @disable_idlists_sync = disable_idlists_sync
    @disable_rulesets_sync = disable_rulesets_sync
    @disable_sorbet_logging_handlers = disable_sorbet_logging_handlers

    dcs_url = download_config_specs_url || 'https://api.statsigcdn.com/v2/download_config_specs/'
    unless dcs_url.end_with?('/')
      dcs_url += '/'
    end
    @download_config_specs_url = dcs_url

    @environment = environment.is_a?(Hash) ? environment : nil
    @get_id_lists_url = get_id_lists_url || 'https://statsigapi.net/v1/get_id_lists'
    @idlist_threadpool_size = idlist_threadpool_size
    @idlists_sync_interval = idlists_sync_interval
    @local_mode = local_mode
    @log_event_url = log_event_url || 'https://statsigapi.net/v1/log_event'
    @logger_threadpool_size = logger_threadpool_size
    @logging_interval_seconds = logging_interval_seconds
    @logging_max_buffer_size = [logging_max_buffer_size, 1000].min
    @network_timeout = network_timeout
    @post_logs_retry_backoff = post_logs_retry_backoff
    @post_logs_retry_limit = post_logs_retry_limit
    @rules_updated_callback = rules_updated_callback
    @ruleset_id_list_retry_limit = ruleset_id_list_retry_limit
    @rulesets_sync_interval = rulesets_sync_interval
    @user_persistent_storage = user_persistent_storage
  end
end
