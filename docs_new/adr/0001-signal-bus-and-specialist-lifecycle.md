# ADR-0001: Deterministic Signal Bus Isolation and Specialist Lifecycle

- **Status:** Proposed  
- **Date:** 2025-11-09  
- **Owner:** Synapse Runtime Team

## Context

Deep-review orchestration currently relies on a single global `Jido.Signal.Bus` (`:synapse_bus`) and a single `Synapse.AgentRegistry` (`:synapse_registry`) started in `Synapse.Application` (synapse_new/lib/synapse/application.ex:9-32). When a `review.request` is classified as `:deep_review`, the coordinator:

1. Calls `AgentRegistry.get_or_spawn/4` for `"security_specialist"` and `"performance_specialist"` (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:246-295).
2. Immediately republish the original signal to the bus to give the specialists a second chance to see it (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:271-305).
3. Waits for specialist readiness by calling `wait_for_specialists_ready/3`.

This design exhibits three systemic problems:

* **Readiness gates never fire.** Specialists are registered under string IDs (e.g., `"security_specialist"`), but `wait_for_specialists_ready/3` uses atom IDs (`:security_specialist`) when calling `AgentRegistry.lookup/2`, so it always logs “not found” and proceeds even when the specialist is still booting (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:246-321).
* **Signals are replayed blindly.** `republish_review_request/2` unconditionally re-emits every deep-review request even if both specialists were already alive and subscribed, causing duplicate work, double telemetry, and, in the worst case, a second round of results arriving after the coordinator already marked the review complete.
* **No runtime crash detection.** Unlike the tests (e.g., synapse_new/test/synapse/agents/coordinator_agent_server_test.exs:198-244), production code never monitors specialist processes or times out pending reviews. When a specialist crashes mid-review (observed during `mix test --trace`), the coordinator simply waits for `collect_results` to expire (~10 s) before returning success, masking the failure.

Because the bus and registry are global, additional symptoms follow:

* Tests that rely on dedicated buses require ad-hoc helpers (`Synapse.TestSupport.SignalRouterHelpers`), but production code offers no analogous per-review isolation. A single slow or crashing specialist blocks every coordinator because all of them share the same `"security_specialist"` PID.
* There is no way to prove (or even observe) that a new specialist actually subscribed before the coordinator republishes the signal.

## Decision

1. **Introduce an explicit Specialist Supervisor per bus/registry pair.**  
   - Create `Synapse.SpecialistSupervisor` that owns the security and performance specialists for a given `{bus, registry}` tuple.  
   - `AgentRegistry.get_or_spawn/4` will return `{:ok, pid, new?}` so the coordinator knows whether it needs to backfill missed signals.

2. **Track readiness with string IDs and explicit ack signals.**  
   - Specialists emit a `review.specialist_ready` message once they subscribe, and the coordinator waits on those acknowledgements instead of polling the registry with mismatched IDs.  
   - The poller falls back to `await_signal/2` with a 100 ms cadence (no `Process.sleep/200`) to keep the tests deterministic.

3. **Replace blind republish with deterministic replay.**  
   - If `new?` is `true`, the coordinator replays the original signal directly to the new specialist PID via `GenServer.cast`, bypassing the public bus.  
   - If a specialist was already running, no extra publication occurs, eliminating duplicate work and the false-positive “long running” tests.

4. **Monitor specialists for the lifetime of the review.**  
   - `handle_deep_review/4` records `Process.monitor/1` refs and aborts the review when a specialist dies before sending a result.  
   - Crash reasons are surfaced via a new `review.summary` status (`:failed`) instead of logging warnings while still claiming success.

## Consequences

* Specialists become ordinary supervised children with predictable lifecycles; restarting them no longer requires ad-hoc registry lookups.
* Coordinators can run in parallel (different buses/registries), because specialist IDs are namespaced by supervisor instance (`{bus, "security_specialist"}`).
* Test code and production code share the same isolation story; helpers such as `Synapse.TestSupport.SignalRouterHelpers` simply wrap the new supervisor API.
* Removing the unconditional `republish_review_request/2` eliminates the 5 s “slow test” slots that were masking specialist crashes.

## Alternatives Considered

* **Keep the global bus but throttle with back-pressure.**  
  Rejected because it still allows a single broken specialist to starve the entire system.
* **Replay signals from the bus log.**  
  Rejected because we cannot differentiate “needs replay” vs “already processed” without tracking which specialists were actually spawned.

## References

* Coordinator deep-review flow (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:243-321)
* Specialist readiness mismatch (same file, string IDs at lines 248-258 vs atom IDs at line 271)
* Test-only monitoring (synapse_new/test/synapse/agents/coordinator_agent_server_test.exs:198-244)
