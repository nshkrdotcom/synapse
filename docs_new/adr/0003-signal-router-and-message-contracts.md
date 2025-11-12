# ADR-0003: Introduce Synapse Signal Router & Message Contracts

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Runtime Team

## Context

Every agent and workflow in Synapse publishes and subscribes directly to `Jido.Signal.Bus`. Payload structure, topics, and expectations are implicit:

- Coordinator subscribes to `"review.request"` / `"review.result"` and republishes the request after spawning specialists (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:214-358).
- Specialists subscribe to `"review.request"` and emit `"review.result"` (e.g., synapse_new/lib/synapse/agents/security_agent_server.ex:130-222).
- Tests manually subscribe to patterns using `Synapse.TestSupport.SignalRouterHelpers` (test/support/signal_bus_helpers.ex:90-144).

This approach has several drawbacks:

1. **No schema enforcement.** A typo in `signal.type` or missing fields goes unnoticed until downstream code pattern matches and crashes.
2. **Inconsistent delivery semantics.** Some modules expect at-most-once behavior, others rely on manual replay; there’s no central contract around ack, replay, or durable subscriptions.
3. **Difficult to extend beyond reviews.** Adding new workflows (e.g., incident response, doc generation) would require every agent to know the exact topics and payload shapes.

## Decision

Add a `Synapse.SignalRouter` layer that sits between application code and `Jido.Signal.Bus`. The router will:

* Provide typed publish/subscribe helpers for canonical topics (review.request, review.result, review.summary, specialist.ready, etc.), including schema validation.
* Encode delivery policy (e.g., “requests are acked by coordinator only”, “ready signals expire after 1s”), freeing agents from low-level bus calls.
* Offer per-runtime registries of routes so additional workflows can register new message types without touching the router core.

Key API sketch:

```elixir
{:ok, router} = Synapse.SignalRouter.start_link(bus: runtime.bus)
Synapse.SignalRouter.publish(router, :review_request, payload)
Synapse.SignalRouter.subscribe(router, :review_result, target: self())
```

Router modules can also expose `cast_to_specialist(router, specialist_id, signal)` to implement targeted replay logic without leaking PID knowledge.

## Consequences

* Agents/workflows depend on the router instead of raw `Jido.Signal.Bus`, improving readability and testability.
* Schema validation happens once; invalid messages fail fast with clear errors.
* Routing metadata (e.g., correlation IDs, deadlines) can be injected automatically, enabling richer telemetry and tracing.

## Alternatives Considered

1. **Document conventions only.** Rejected because conventions alone will not prevent regression; we already suffer from mismatched IDs and duplicate publications.
2. **Use a third-party message bus abstraction.** Rejected because we need tight integration with runtime handles, not a general-purpose queue.

## Related ADRs

* ADR-0002 (Runtime Kernel) – the router becomes another runtime child.
* ADR-0001 – targeted replay and crash monitoring rely on consistent message contracts; the router enforces them.
