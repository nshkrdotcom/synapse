# Resilience & Retry Policy

## Problem Statement
- ReqLLM currently performs a single HTTP attempt; any network hiccup or provider throttling fails the request.
- Jido retries the action once, but without backoff or 429-aware logic.
- No circuit-breaker or health evaluation exists for stubbornly failing providers.

## Design Goals
1. Introduce configurable retry policies with exponential backoff.
2. Handle rate limiting (HTTP 429) with Retry-After awareness.
3. Avoid cascading failures by short-circuiting unhealthy providers.

## Proposed Architecture
- Leverage Req middleware (`Req.Steps.retry/2`) for transient errors:
  - Retry on specific conditions: 408, 429, >=500, transport errors like `:timeout`, `:econnrefused`.
  - Use exponential backoff with jitter (e.g., base 300ms, max 5 attempts).
- Maintain per-profile circuit state (ETS or Agent) capturing:
  - Recent failure count.
  - Last success timestamp.
  - Circuit status (`:closed`, `:open`, `:half_open`).
- If circuit is open, raise a `Jido.Error` immediately with guidance and telemetry increment.

## Configuration
- Extend profile config with `retry: [max_attempts: 3, base_backoff_ms: 300, max_backoff_ms: 5_000]`.
- Allow overrides per request via options (`opts[:retry]`).
- Provide sensible defaults per provider based on SLA.

## Implementation Steps
1. Add retry middleware and integrate with provider modules for custom logic (e.g., parse Retry-After headers).
2. Implement circuit breaker module with ETS cache and expose `Synapse.ReqLLM.allow_request?/1`.
3. Emit telemetry events for retry attempts and circuit transitions.

## Future Work
- Add request rate limiting per profile using token bucket algorithm.
- Provide admin tooling to reset circuits or inspect current status.
