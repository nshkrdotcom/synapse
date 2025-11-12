# Observability & Telemetry Plan

## Problem Statement
- The LLM integration lacks telemetry, structured logging, or metrics.
- We cannot track latency, token usage, error rates, or profile popularity.
- Debugging production incidents requires ad hoc `IO.inspect` statements.

## Goals
1. Emit telemetry for request start/stop/error with consistent metadata.
2. Expose token usage metrics for cost tracking and budget enforcement.
3. Provide structured logging hooks without polluting standard output.

## Telemetry Design
- Events:
  - `[:synapse, :llm, :request, :start]`
  - `[:synapse, :llm, :request, :stop]`
  - `[:synapse, :llm, :request, :exception]`
- Measurements:
  - Start: `%{system_time: System.system_time()}`
  - Stop: `%{duration: native_time}`
  - Exception: `%{duration: native_time}`
- Metadata:
  - `%{profile: :openai, model: "gpt-5-nano", provider: Synapse.Providers.OpenAI, request_id: uuid, token_usage: %{prompt: 10, completion: 20}}`

## Logging
- Optionally integrate with `Logger` to emit debug/info logs when telemetry handlers are installed.
- Avoid logging raw prompts or provider responses unless explicitly enabled via config.

## Implementation Steps
1. Add telemetry emission in `Synapse.ReqLLM` around request lifecycle.
2. Capture token usage metadata in provider `parse_response/2` callbacks.
3. Document how to attach telemetry handlers (e.g., StatsD, Prometheus exporters).

## Future Enhancements
- Expose metrics dashboards (Grafana) for latency and error rates.
- Integrate with tracing (OpenTelemetry) for distributed request tracking.
