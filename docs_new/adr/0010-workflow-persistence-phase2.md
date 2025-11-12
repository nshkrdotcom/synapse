# ADR-0010: Workflow Persistence Phase 2 – Distributed Resilience & Saga Semantics

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Runtime Team

## Context

ADR-0009 establishes the foundational Postgres snapshot store for workflow
persistence. That design intentionally limits scope to single-runtime usage:
no cross-node coordination, minimal locking, and best-effort durability.
However, Synapse’s roadmap includes multi-runtime deployments (multiple
coordinators sharing a persistence layer), human-in-the-loop pauses, saga-style
compensation, and audit requirements such as:

* deterministic resume even when the same workflow is retried concurrently;
* idempotent step execution despite duplicate signals or retries;
* rollback hooks for multi-agent compensation chains; and
* observable “total recall” (complete lifecycle trace) across distributed nodes.

Phase 2 extends the persistence layer to meet those requirements without
rewriting the engine again.

## Decision

1. **Add a workflow execution state machine.** Define canonical states
   (`pending`, `running`, `paused`, `waiting_human`, `resuming`, `completed`,
   `failed`, `compensated`) and enforce transitions at the DB level (Postgres
   CHECK constraints + application guards).

2. **Introduce optimistic locking & leases.**
   - Add `lock_version` to `workflow_executions`.
   - Implement lease columns (`lease_owner`, `lease_expires_at`). Coordinators
     must acquire a lease before executing/resuming a workflow. Automatic
     expiry lets other nodes take over after a crash.

3. **Saga + compensation metadata.**
   - Extend the schema with `pending_compensations` + `completed_compensations`
     arrays to record which steps require rollback.
   - Engine adds hooks to run compensation steps when a failure occurs and to
     persist the outcome for auditing.

4. **Idempotency surfaces.**
   - Each step result stored with a deterministic `step_execution_id`
     (hash of request_id + step_id + attempt). Engine checks the DB before
     invoking an action; if an identical execution is already recorded, the
     cached result is reused instead of re-running the action.

5. **Total recall API + telemetry.**
   - Build `Synapse.Workflow.Recall` API for querying timelines, diffing resume
     attempts, and exporting audit logs.
   - Emit telemetry (`[:synapse, :workflow, :lease, ...]`,
     `[:synapse, :workflow, :saga, ...]`) for observability.

6. **Distributed coordination hooks.**
   - Provide pluggable locker behaviour so installations can swap Postgres-row
     locking for Redis, etc., but default to Postgres `SELECT ... FOR UPDATE`
     with short leases.
   - Update `Synapse.Runtime` to register workflows in the Signal Router so
     other runtimes can observe resume/lease events (preparing for eventual
     multi-cluster orchestration).

## Consequences

* Stronger guarantees: once Phase 2 lands, we can promise exactly-once step
  execution (modulo user-defined action idempotency) and recoverable sagas.
* Complexity increases: more DB writes per step, need for background cron to
  clean expired leases/compensation queues, and migration strategy for existing
  snapshots.
* Engine API surface grows (resume/compensate hooks, idempotent reads). Before
  adopting Phase 2, teams must update orchestrators to understand leases.

## Alternatives Considered

1. **Adopt Temporal/Cadence now.** Would provide most of these features but
   require rewriting orchestrators for a new programming model.
2. **Keep Phase 1 forever + rely on external queue idempotency.** Insufficient
   for regulated environments needing audit/rollback guarantees.

## Migration Plan

1. Ship Phase 1 (ADR-0009) and verify persistence works for chain workflows.
2. Roll out the state-machine + leases behind feature flags per runtime.
3. Incrementally enable compensation hooks for specialists that already expose
   rollback actions.
4. Expand tests: chaos tests that kill coordinators mid-saga must show auto
   resume on another node without duplicate side effects.

## References

* ADR-0009 – Base snapshot schema/Repo integration.
* ADR-0007 – Human-in-the-loop escalation (ties into paused/waiting states).
* ADR-0008 – Agent state store (can share persistence primitives).
