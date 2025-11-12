# ADR-0002: Extract Synapse Runtime Kernel from Phoenix Adapters

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Runtime Team

## Context

Synapse currently boots everything inside `Synapse.Application` (synapse_new/lib/synapse/application.ex:9-32): Phoenix telemetry, PubSub, the HTTP endpoint, and—critically—the only instances of `Jido.Signal.Bus` and `Synapse.AgentRegistry`. Every module assumes those globally registered names (`:synapse_bus`, `:synapse_registry`). Tests that need isolation reimplement their own registries/buses manually (`setup_test_bus/2`, custom registries), and non-Phoenix use cases (CLI demos, other host apps) must spin up the entire Phoenix tree just to exercise agents.

This coupling creates several problems:

1. **No reusable runtime:** You cannot start a Synapse orchestration stack inside another BEAM app (or a supervised test) without copy/pasting application-level boot code.
2. **Global state collisions:** The default names cause conflicts whenever multiple runtimes need to coexist (e.g., integration tests vs. dev server). We’re already working around this by namespacing specialist IDs, but the root cause is the lack of runtime encapsulation.
3. **Poor layering for future adapters:** Phoenix/HTTP is just one way to interact with the runtime. CLI, GRPC, or background job adapters should be optional, but today they are baked into the only supervision tree we have.

## Decision

Introduce a **Synapse Runtime Kernel**—a supervision tree that owns:

* a Signal Bus (or buses) configured via options,
* one or more `Synapse.AgentRegistry` processes,
* optional Specialist Supervisors (per ADR-0001),
* shared configuration (ReqLLM, telemetry), and
* instrumentation hooks.

Adapters (Phoenix, CLI demos, tests) will call `Synapse.Runtime.start_link/1` (or child_spec) to obtain an isolated kernel. The Phoenix app becomes an adapter that starts a runtime as one child and the HTTP endpoint as another.

Key properties:

* **Name-free startup:** Callers receive `{runtime, bus, registry}` references instead of relying on atoms like `:synapse_bus`.
* **Multiple runtimes per VM:** Each runtime supervises its own bus/registry; adapters stash the handles in their context.
* **Configurable topology:** Options allow single-bus vs. multi-bus, enabling future workloads without code changes inside `Synapse.Application`.

## Consequences

* All modules that currently call `Jido.Signal.Bus.publish(:synapse_bus, ...)` or `Synapse.AgentRegistry.lookup(:synapse_registry, ...)` must accept runtime handles. This is an invasive change but necessary for deterministic orchestration.
* Phoenix startup becomes a thin wrapper; tests no longer need to `start_supervised!({Synapse.AgentRegistry, ...})` themselves because the runtime exposes helper functions.
* Observability improves: each runtime can emit metrics using its own IDs, making it easy to run load tests without colliding with the dev server.

## Alternatives Considered

1. **Keep Phoenix as the root supervisor but allow multiple buses/registries.**  
   Rejected because every non-Phoenix consumer would still import Phoenix deps and sup trees just to run Synapse.

2. **Make bus/registry names configurable application env.**  
   Rejected because env-driven names still rely on globals and do not solve the layering or multi-instance problem.

## Related ADRs

* ADR-0001 (Signal Bus Isolation & Specialist Lifecycle) depends on the ability to spin up dedicated runtime instances.
* Future ADRs covering workflow orchestration and telemetry will treat “runtime kernel” as the foundational layer.
