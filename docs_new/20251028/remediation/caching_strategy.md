# Response Caching Strategy

## Problem Statement
- Identical prompts across workflows trigger repeated LLM calls, increasing cost and latency.
- There is no shared cache for `Synapse.ReqLLM` responses.
- Downstream consumers cannot leverage cache hints or invalidation policies.

## Goals
1. Introduce an opt-in cache for deterministic prompts.
2. Support cache invalidation based on TTL or custom rules.
3. Track cache hit/miss metrics for optimization.

## Design Overview
- Cache store: use `Cachex` (if available) or ETS backed by supervisor-managed process.
- Cache key: `:erlang.phash2({profile, model, params_without_non_cacheable_fields})`.
- Data stored: LLM response payload + metadata + timestamp.
- TTL: configurable via runtime config (e.g., `cache: [ttl: :timer.minutes(5)]`).
- Allow callers to bypass cache with `opts[:cache] = false` or refresh with `:refresh`.

## Implementation Steps
1. Create `Synapse.ReqLLM.Cache` module abstracting cache operations.
2. Integrate caching into `chat_completion/2` coordinator before dispatching provider call.
3. Emit telemetry events for hits/misses.
4. Provide CLI tooling or telemetry dashboards to inspect cache usage.

## Considerations
- Avoid caching prompts that include dynamic timestamps or non-deterministic inputs.
- Provide hooks for cache invalidation when models update.
- Ensure sanitized storage to prevent leaking sensitive data.
