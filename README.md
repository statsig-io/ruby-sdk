# Statsig Ruby Server SDK

[![build-and-test](https://github.com/statsig-io/ruby-sdk/actions/workflows/build-and-test.yml/badge.svg?branch=main)](https://github.com/statsig-io/ruby-sdk/actions/workflows/build-and-test.yml)

The Statsig Ruby SDK for multi-user, server side environments. If you need a SDK for another language or single user client environment, check out our [other SDKs](https://docs.statsig.com/#sdks).

Statsig helps you move faster with Feature Gates (Feature Flags) and Dynamic Configs. It also allows you to run A/B tests to validate your new features and understand their impact on your KPIs. If you're new to Statsig, create an account at [statsig.com](https://www.statsig.com).

## Getting Started

Check out our [SDK docs](https://docs.statsig.com/server/rubySDK) to get started.

## StatsigOptions

| Option | Description | Default |
| --- | --- | --- |
| `bootstrap_values` | String representing all rules for initialization | `nil` |
| `data_store` | Class extending IDataStore for common data store (e.g. Redis) | `nil` |
| `disable_diagnostics_logging` | Should diagnostics be logged | `false` |
| `disable_evaluation_memoization` | Disable memoization of evaluation results | `false` |
| `disable_idlists_sync` | Disable background syncing for id lists | `false` |
| `disable_rulesets_sync` | Disable background syncing for rulesets | `false` |
| `disable_sorbet_logging_handlers` | Disable Sorbet type safety logging | `false` |
| `download_config_specs_url` | URL for download_config_specs | `https://api.statsigcdn.com/v2/download_config_specs/` |
| `environment` | Hash for environment variables (e.g. `{ "tier" => "development" }`) | `nil` |
| `get_id_lists_url` | URL for get_id_lists | `https://statsigapi.net/v1/get_id_lists` |
| `idlist_threadpool_size` | Number of threads for syncing IDLists | `3` |
| `idlists_sync_interval` | Interval (in seconds) to poll for id list changes | `60` |
| `local_mode` | Restricts the SDK to not issue any network requests | `false` |
| `log_event_url` | URL for log_event | `https://statsigapi.net/v1/log_event` |
| `logger_threadpool_size` | Number of threads for posting event logs | `3` |
| `logging_interval_seconds` | How often to flush logs to Statsig | `60` |
| `logging_max_buffer_size` | Maximum number of events to batch before flushing | `1000` |
| `network_timeout` | Number of seconds before a network call is timed out | `30` |
| `post_logs_retry_backoff` | Backoff time/function between retries | `nil` |
| `post_logs_retry_limit` | Number of times to retry failed log events | `3` |
| `rules_updated_callback` | Callback function called when rulesets are updated | `nil` |
| `ruleset_id_list_retry_limit` | Number of times to retry fetching rulesets and id lists | `3` |
| `rulesets_sync_interval` | Interval (in seconds) to poll for configuration changes | `10` |
| `user_persistent_storage` | Storage adapter for persisted values | `nil` |

## Testing

Each server SDK is tested at multiple levels - from unit to integration and e2e tests. Our internal e2e test harness runs daily against each server SDK, while unit and integration tests can be seen in the respective github repos of each SDK. The `server_sdk_consistency_test` runs a validation test on local rule/condition evaluation for this SDK against the results in the statsig backend.
