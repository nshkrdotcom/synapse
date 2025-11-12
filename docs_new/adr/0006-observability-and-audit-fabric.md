# ADR-0006: Observability & Audit Fabric

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Observability Team

## Context

Current telemetry support is minimal: `Synapse.ReqLLM` emits `[:synapse, :llm, :request, ...]` events, and `Synapse.Telemetry` exposes a single `emit_compensation/1` helper. There is no unified tracing for workflows, no persistent audit log of signals/results, and no standardized correlation IDs across layers. Tests rely on logs to assert behavior, indicating a lack of machine-readable traces.

Problems:

1. **Sparse instrumentation.** Coordinator, specialists, and workflows mostly log via `Logger.debug/info`; consumers cannot aggregate metrics or traces across runs.
2. **No audit trail.** Finished reviews only emit `review.summary` signals; we don’t persist step-level decisions, making post-mortems difficult.
3. **Per-runtime visibility missing.** Once we introduce multiple runtimes (ADR-0002), we’ll need per-runtime metrics and dashboards; current telemetry assumes global state.

## Decision

Build an Observability & Audit Fabric consisting of:

* **Telemetry namespace conventions** – every major component (runtime, router, workflow engine, LLM gateway) emits start/stop/exception events with shared metadata (`runtime_id`, `request_id`, `workflow_id`, `specialist_id`).
* **Structured audit log** – optionally persist critical events (review started, specialist spawned, summary emitted, gateway budget trip) to an ETS/Mnesia/DB-backed log for replay/debugging.
* **Tracing helpers** – propagate context (request_id, workflow_id) through Signal Router and workflow engine so distributed traces can be reconstructed (via OpenTelemetry or a lightweight span struct).

## Consequences

* Modules must accept and propagate context maps (or use process dictionaries) so correlation IDs are available for telemetry.
* Additional storage/compute for audit logs; we can start with ETS + periodic drain to disk or user-provided callback.
* Operators gain dashboards/alerts (LLM latency, specialist crash rate, workflow success rate).

## Alternatives Considered

1. **Rely on Phoenix logging + manual Kibana queries.**  
   Rejected: not sufficient for multi-runtime debugging or automation.

2. **Adopt full OpenTelemetry from day one.**  
   Deferred: we can start with Telemetry events + optional OTEL exporter, but the ADR is to define clear semantics now so OTEL adoption later is straightforward.

## Related ADRs

* ADR-0002 (runtime IDs) – telemetry metadata must include runtime identifiers.
* ADR-0003 (router) – ensures all signals carry correlation metadata.
* ADR-0004 (workflow engine) – engine emits per-step telemetry.
