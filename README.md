# Statsig Ruby Server SDK

[![build-and-test](https://github.com/statsig-io/ruby-sdk/actions/workflows/build-and-test.yml/badge.svg?branch=main)](https://github.com/statsig-io/ruby-sdk/actions/workflows/build-and-test.yml)

The Statsig Ruby SDK for multi-user, server side environments. If you need a SDK for another language or single user client environment, check out our [other SDKs](https://docs.statsig.com/#sdks).

Statsig helps you move faster with Feature Gates (Feature Flags) and Dynamic Configs. It also allows you to run A/B tests to validate your new features and understand their impact on your KPIs. If you're new to Statsig, create an account at [statsig.com](https://www.statsig.com).

## Getting Started

Check out our [SDK docs](https://docs.statsig.com/server/rubySDK) to get started.

## Config download fallback URLs

Set `download_config_specs_fallback_urls` to an ordered list of full config-download endpoint bases. The SDK appends the server secret and `.json` to each base, tries each URL after the primary fails, and stops at the first valid config response. For example, to use the default CDN first and an explicitly configured alternative second:

```ruby
options = StatsigOptions.new(
  download_config_specs_fallback_urls: [
    'https://api.statsig.com/v2/download_config_specs/'
  ]
)
Statsig.initialize('secret-your-server-key', options)
```

The primary remains `download_config_specs_url` (the Statsig CDN by default). The fallback list also works when the primary is the default CDN. Duplicate URLs and URLs equal to the primary are skipped after trailing-slash normalization.

| `download_config_specs_fallback_urls` | Behavior |
| --- | --- |
| `nil` (default) | Preserve `fallback_to_statsig_api`: when true and the primary is a custom URL, fall back to the Statsig CDN. |
| `[]` | Disable fallback, even when `fallback_to_statsig_api` is true. |
| Non-empty list | Try the listed URLs in order after a primary failure, regardless of `fallback_to_statsig_api`. |

Fallbacks run during initialization after a failed primary request. During background sync, they run on every fifth failed primary poll. Each fallback gets one request and uses the configured `network_timeout`. Direct-origin use is opt-in; choose endpoints appropriate for your deployment's capacity and rate limits.

## Testing

Each server SDK is tested at multiple levels - from unit to integration and e2e tests. Our internal e2e test harness runs daily against each server SDK, while unit and integration tests can be seen in the respective github repos of each SDK. The `server_sdk_consistency_test` runs a validation test on local rule/condition evaluation for this SDK against the results in the statsig backend.
