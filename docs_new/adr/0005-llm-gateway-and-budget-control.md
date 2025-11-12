# ADR-0005: LLM Gateway with Budget Control & Circuit Breakers

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Platform Team

## Context

`Synapse.ReqLLM` is the sole gateway to external LLM providers. It accepts a map of params, resolves config from `Application.get_env/2`, and issues synchronous HTTP calls via Req (synapse_new/lib/synapse/req_llm.ex:1-620). While it supports multiple “profiles” and basic retry/backoff, the current design has notable gaps:

1. **Global configuration, no per-runtime overrides.** Tests and adapters mutate application env (e.g., `Application.put_env(:synapse, :req_llm_module, FakeReqLLM)`), leading to race conditions between concurrent runtimes.
2. **No resource or budget enforcement.** Nothing tracks token usage, call counts, or per-profile quotas—even though we already emit telemetry with token usage. A runaway workflow can exceed provider limits without tripping a breaker.
3. **Synchronous, blocking calls only.** Workflows must wait for the Req call to finish; there is no queueing or async pipeline to decouple LLM latency from orchestrator responsiveness.
4. **Provider-specific logic is implicit.** `resolve_provider_module/1` infers the provider from `:payload_format`; there’s no explicit capability negotiation or shared contract for new providers.

## Decision

Introduce a **dedicated LLM Gateway service** inside the Synapse runtime with the following properties:

* **Runtime-bound configuration.** Gateway instances are started per runtime (ADR-0002), accept config structs, and expose APIs instead of relying on global application env.
* **Budget & quota enforcement.** Maintain per-profile/token budgets, request rate meters, and circuit breakers. Workflows receive structured errors when a budget is exhausted instead of discovering overages via provider exceptions.
* **Unified provider adapters.** Define behaviour modules (`Synapse.LLM.Provider`) with explicit callbacks (build_request, parse_response, supports_stream?/0). Providers register their capabilities at runtime.
* **Async execution options.** Support both sync (`Gateway.call/2`) and async (`Gateway.enqueue/2`) modes. Async mode returns a reference and delivers results via the Signal Router, enabling orchestrators to await results without blocking the caller process.

## Consequences

* Workflows and actions now depend on `Synapse.LLM.Gateway` instead of `Synapse.ReqLLM`. Existing modules that call `Synapse.ReqLLM.chat_completion/2` will be updated to accept a gateway handle.
* Fake/test gateways become lightweight processes created per test, eliminating cross-test contamination.
* Budget enforcement introduces new failure cases (e.g., :budget_exceeded), so orchestrators must handle those explicitly—preferably via the declarative workflow engine (ADR-0004).

## Alternatives Considered

1. **Keep global ReqLLM but add mutexes around Application env.**  
   Rejected: still brittle, no budget enforcement, duplicates logic per test.

2. **Outsource to an external proxy service.**  
   Rejected: adds operational burden; we need tight integration with runtime telemetry and workflows.

## Related ADRs

* ADR-0002 ensures gateways can be started per runtime.
* ADR-0004 uses the gateway in workflow steps.
* Upcoming telemetry ADR will leverage gateway metrics for dashboards and alerts.
