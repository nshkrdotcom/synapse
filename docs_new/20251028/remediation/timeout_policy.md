# Timeout Policy Redesign

## Problem Statement
- Current configuration sets `receive_timeout` to 30 minutes for all providers, trading reliability for responsiveness.
- Industry-standard LLM calls should fail fast (30–60 seconds) or stream partial results.
- There is no per-request override or cancellation mechanism.

## Objectives
1. Establish sane default timeouts per provider (connect, pool, receive).
2. Allow callers to override timeouts per request when needed.
3. Support cancellation or deadline propagation from upstream (e.g., workflow time budgets).

## Proposed Strategy
- Default timeouts:
  - `connect_timeout`: 5_000 ms
  - `pool_timeout`: 5_000 ms
  - `receive_timeout`: 60_000 ms (configurable via application env).
- Expose `opts[:timeout]` or `opts[:receive_timeout]` in `chat_completion/2`.
- In workflows, respect Jido action compensation config (e.g., `timeout: 5_000`) to determine request deadlines.

## Implementation Steps
1. Update profile schema to accept `timeouts` map or richer structure.
2. In `Synapse.ReqLLM`, merge default timeouts with per-request overrides before building the Req request.
3. Provide helper `Synapse.ReqLLM.deadline_timeout/2` that calculates remaining time for the request based on workflow context.
4. Adjust tests to reflect shorter defaults and override cases.

## Future Enhancements
- Support streaming fallback: if response exceeds threshold, switch to streaming API.
- Surface timeout metrics for visibility and automatic scaling decisions.
