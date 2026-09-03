# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- This SDK is a **standalone evaluator**. It reimplements rule and condition evaluation in
  Ruby rather than binding to statsig-server-core, so evaluator behavior can silently drift
  from the Console.
- The Console evaluates with `statsig-rust` (in `statsig-server-core`). Treat it as the
  reference implementation for any evaluation question; `statsig-io/go-sdk` is the closest
  architectural match (another standalone evaluator) but Rust wins where the two differ.
- Run the tests with `bundle exec rake test`. `CountryLookupTest#test_lookup` needs the
  `test_api_key` env var and live network, so it errors on a plain local run.
- Spec fixtures live in `test/data/*.json`. They use the v2 download-config-specs shape:
  rules reference conditions by hash into a top-level `condition_map`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
