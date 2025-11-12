# Specialist Runtime Lifecycle

Synapse now runs every specialist agent (security, performance, etc.) under the
`Synapse.SpecialistSupervisor` dynamic supervisor. This supervisor is started as part of
`Synapse.Application` and guarantees that specialists continue running even if individual
coordinators crash or restart.

Key points:

1. **Namespaced Agent IDs** – Specialists are registered in `Synapse.AgentRegistry` using
   bus-scoped identifiers (`"#{bus}|security_specialist"`), so multiple runtimes can coexist without PID clashes.

2. **Ready Signals** – After subscribing to `review.request`, each specialist publishes a
   `review.specialist_ready` signal with metadata (`agent`, `bus`, `timestamp`). Tests and orchestrators can
   subscribe to this type to wait for deterministic readiness instead of sleeping.

3. **Targeted Replay** – When a new specialist is spawned mid-review, the coordinator delivers the original
   `review.request` directly via `GenServer.cast/2`. Telemetry event `[:synapse, :specialist, :replay]` is emitted for observability.

4. **Crash Monitoring** – Coordinators monitor specialists per review. If a specialist crashes before responding,
   the coordinator emits a failed `review.summary` and telemetry event `[:synapse, :specialist, :crash]`.

5. **Testing** – `Synapse.TestSupport.SignalRouterHelpers` can subscribe to `review.specialist_ready` to assert
   readiness in tests. Coordinators in tests no longer rely on `Process.sleep`.

This lifecycle is the foundation for the runtime kernel (ADR‑0002) and signal router (ADR‑0003). Future runtimes
should start their own `Synapse.SpecialistSupervisor` instances or use the provided supervisor with custom names.
