# Remediation Plan – ADR-0003

## Objective

Wrap `Jido.Signal.Bus` with a `Synapse.SignalRouter` that enforces message contracts, centralizes publish/subscribe ergonomics, and supports targeted delivery without leaking process IDs.

## Tasks

1. **Router Implementation**
   - [x] Create `Synapse.SignalRouter` with `start_link/1`, `publish/3`, `subscribe/3`.
   - [x] Define canonical topics (`:review_request`, `:review_result`, `:review_summary`, `:specialist_ready`, etc.) and schema modules under `Synapse.Signal`.
   - [x] Integrate telemetry hooks inside the router so each publish/receive automatically emits metrics.

2. **Runtime Integration**
   - [x] Start the router inside `Synapse.Runtime` (per ADR-0002) and expose it via the runtime struct.
   - [x] Update coordinator and specialists to call `router.publish(:review_request, payload)` instead of `Jido.Signal.Bus.publish/2`.
   - [x] Replace manual `subscribe` calls (`Jido.Signal.Bus.subscribe/...`) with `router.subscribe(topic, opts)`.

3. **Schema Validation**
   - [x] Implement schema modules (e.g., `Synapse.Signal.ReviewRequest`) using `NimbleOptions` or `Ecto.Schema` for strong typing.
   - [x] Router should validate both outgoing and incoming payloads; invalid data raises a descriptive error before reaching business logic.

4. **Targeted Delivery Helpers**
   - [x] Add `Synapse.SignalRouter.cast_to_specialist/3` (or similar) that resolves the specialist’s PID/queue and sends the original signal, replacing the bespoke `GenServer.cast` logic now living inside `CoordinatorAgentServer`.
   - [x] Provide ack/retry helpers so future workloads can request durable delivery.

5. **Testing & Tooling**
   - [x] Update `Synapse.TestSupport.SignalRouterHelpers` to work with the router (or deprecate it in favor of router-specific helpers).
   - [x] Adapt all tests to rely on router APIs; add coverage to ensure schema validation fails on malformed payloads.

## Verification

* Coordinators, specialists, and workflows no longer call `Jido.Signal.Bus` directly.
* Test helpers publish/await signals through the router and assert on structured payloads.
* Running `mix test --trace` shows consistent signal types; invalid payload e2e tests fail at the router with clear messages.

## Risks

* **Migration churn:** Touches every module that publishes or subscribes. Mitigate by introducing the router, then migrating files module-by-module with feature flags (router optional at first).
* **Performance:** Extra validation adds work per signal. Mitigate by keeping schemas lightweight and benchmarking before/after.
