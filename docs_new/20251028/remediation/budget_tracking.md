# Request Budget Tracking & Cost Controls

## Problem Statement
- LLM usage has no safeguards against exceeding token or request quotas.
- Finance teams cannot enforce daily/weekly budgets or track per-profile costs.
- Workflows might trigger runaway loops without detection.

## Goals
1. Track tokens and request counts per provider/profile.
2. Enforce configurable budgets (daily, weekly, or rolling).
3. Provide alerting hooks when thresholds are approached or exceeded.

## Proposed Architecture
- Introduce `Synapse.ReqLLM.Budget` module managing counters stored in ETS or persistent storage.
- Configuration (example):
  ```elixir
  config :synapse, Synapse.ReqLLM,
    budget: [
      default: [daily_tokens: 100_000, daily_requests: 1_000],
      profiles: %{openai: [daily_tokens: 50_000], gemini: [daily_requests: 500]}
    ]
  ```
- Before executing a request, `Budget.check/2` ensures limits are not exceeded:
  - If near limit, emit telemetry warning.
  - If exceeded, return `{:error, Jido.Error.execution_error("budget exceeded", …)}`.
- After successful response, update counters with actual token usage (from provider metadata).

## Implementation Steps
1. Define configuration schema and validation (integrate with NimbleOptions plan).
2. Build ETS-backed budget tracker with per-day buckets (e.g., keyed by `{profile, date}`).
3. Hook into request pipeline to check budgets pre-request and update post-response.
4. Emit telemetry for budget consumption and threshold crossings.

## Future Enhancements
- Persist counters to database for historical reporting.
- Support per-user or per-workflow budgets.
- Integrate with alerting (Slack, PagerDuty) via telemetry handlers.
