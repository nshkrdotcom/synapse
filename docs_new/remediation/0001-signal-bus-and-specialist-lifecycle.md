# Remediation Plan – ADR-0001

## Goal

Upgrade the coordinator/specialist runtime so that each review runs against specialists that are (a) fully subscribed before work begins, (b) monitored for crashes, and (c) decoupled from the global `:synapse_bus`.

## Workstreams & Tasks

1. **Specialist Supervisor & Namespacing**
   - [ ] Add `Synapse.SpecialistSupervisor` that starts `SecurityAgentServer` and `PerformanceAgentServer` under a dynamic supervisor keyed by `{bus, registry}`.
   - [ ] Extend `Synapse.AgentRegistry.get_or_spawn/4` to return `{:ok, pid, new?}`. Update existing callers accordingly (notably `Synapse.Agents.CoordinatorAgentServer`).
   - [ ] Migrate callers to pass `{bus, registry}`-scoped IDs (e.g., `"security_specialist:#{bus_name}"`) to avoid clashes between coordinators.

2. **Deterministic Readiness Handshake**
   - [ ] Fix the ID mismatch in `wait_for_specialists_ready/3` by using the same string IDs stored in the registry (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:246-321).
   - [ ] Emit a `review.specialist_ready` signal from each specialist after subscribing; update tests to assert on that signal instead of raw sleeps.
   - [ ] Replace the `Enum.each/Process.sleep` poller with a helper that retries every 50–100 ms and fails loudly when a specialist never acknowledges.

3. **Targeted Request Replay**
   - [ ] Remove the unconditional call to `republish_review_request/2` (synapse_new/lib/synapse/agents/coordinator_agent_server.ex:273-305).
   - [ ] When `new?` is true, send the original signal directly to the new specialist PID via `GenServer.cast(pid, {:replay, signal})`; implement a handler in both specialist servers to enqueue the signal.
   - [ ] Add regression tests that assert only one `review.result` per specialist per review.

4. **Crash Monitoring & Failure Surfacing**
   - [ ] Record `Process.monitor/1` refs for every specialist involved in a review; store them in the coordinator’s review state.
   - [ ] If a `:DOWN` arrives before the matching `review.result`, cancel the review and emit a `review.summary` with `status: :failed` plus the crash reason.
   - [ ] Update integration tests (synapse_new/test/synapse/integration/stage_2_orchestration_test.exs) to assert that crashes surface as failures rather than as long waits.

5. **Documentation & Telemetry**
   - [ ] Document the new supervisor lifecycle in `docs/` so tests and production use the same story.
   - [ ] Emit telemetry when targeted replays occur and when a specialist crashes mid-review to aid observability.

## Verification

- `mix test --trace` under `synapse_new` must show <100 ms coordinator tests and zero crashes in the log.
- New regression tests must fail if a second `review.result` arrives for the same specialist/review pair.
- Manual chaos test: kill the performance specialist during a review and verify that the coordinator emits a failed summary within 500 ms.

## Risks & Mitigations

- **Risk:** Supervising specialists per bus increases process count.  
  **Mitigation:** Keep the supervisor lightweight and document how to re-use it in integration tests to avoid duplication.

- **Risk:** Direct casts to specialist PIDs could bypass Signal.Bus middleware.  
  **Mitigation:** Only use direct casts for replay; all normal traffic continues via the bus.
