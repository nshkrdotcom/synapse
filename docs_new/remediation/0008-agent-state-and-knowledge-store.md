# Remediation Plan – ADR-0008

## Objective

Persist specialist agent state (scar tissue, review history, learned patterns) and expose a queryable knowledge store to survive restarts and enable analytics.

## Tasks

1. **Store Interface**
   - [ ] Define `Synapse.AgentStore` behaviour with callbacks (`load(agent_id)`, `save(agent_id, state)`, `stream(agent_id, opts)`).
   - [ ] Provide default ETS + disk snapshot implementation (`Synapse.AgentStore.Local`).

2. **Specialist Integration**
   - [ ] Update `SecurityAgentServer`, `PerformanceAgentServer`, etc., to accept an `:agent_store` handle (default from runtime).
   - [ ] On init, load persisted state; on termination or periodic intervals, save state deltas.
   - [ ] Consider using `:timer.send_interval` for periodic snapshots with backpressure.

3. **Coordinator & API Hooks**
   - [ ] Allow coordinator to request read-only summaries (via store) for scheduling decisions or UI display.
   - [ ] Expose Phoenix/CLI endpoints to inspect agent state (with redactions where needed).

4. **Schema & Versioning**
   - [ ] Introduce version metadata per snapshot; provide migration hooks if agent state schema evolves.
   - [ ] Implement compression/serialization strategy (term_to_binary + zlib, or JSON for compatibility).

5. **Testing**
   - [ ] Provide in-memory mock store for tests; ensure snapshot/load logic is covered.
   - [ ] Add integration test verifying state survives restart (simulate by stopping/starting server).

6. **Docs & Ops**
   - [ ] Document backup/restore procedures for stores.
   - [ ] Allow pluggable adapters for external DBs; provide guidance for production deployments.

## Verification

* Restarting a specialist retains scar tissue/review history.
* Agent store APIs can return historical stats for UI/analytics.
* Tests confirm snapshot frequency and failure handling (e.g., store unavailable) degrade gracefully.

## Risks

* **Consistency vs. performance:** Frequent snapshots may hurt throughput. Mitigate with configurable intervals and incremental deltas.
* **Data privacy:** Stored review diffs might contain sensitive code. Mitigate by redacting or encrypting stored fields and documenting retention policies.
