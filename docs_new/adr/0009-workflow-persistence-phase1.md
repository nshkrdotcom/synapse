# ADR-0009: Workflow Persistence Layer – Phase 1 (Postgres Snapshot Store)

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Runtime Team

## Context

The new `Synapse.Workflow.Engine` (ADR-0004) executes declarative specs and
maintains step results/audit trails in-memory. Coordinators crash or node restarts
currently wipe that state, so long-running orchestrations must be re-run
from scratch. ADR-0008 (agent state & knowledge store) and future pause/resume
features depend on durable workflow snapshots that can be queried, inspected,
and resumed. Tests today fake persistence by keeping context in process state;
production lacks a canonical storage mechanism.

Requirements articulated by runtime/ops:

1. Persist engine state per `request_id` (inputs, spec metadata, partial step
   results, audit entries) so orchestration can resume after a crash.
2. Provide an API for adapters to request the latest snapshot, mark workflows
   as completed/failed, and purge old data.
3. Keep Phase 1 scope single-node and “best effort” (no distributed locking);
   we just need deterministic persistence with Postgres as the source of truth.

## Decision

Implement a Postgres-backed snapshot store using Ecto (`ecto_sql`, `postgrex`):

1. **Introduce `Synapse.Repo`.** Add Ecto dependencies, configure Repo under
   `Synapse.Application`, and provide `mix ecto.*` tasks for migrations.

2. **Create `workflow_executions` table.** Columns:
   - `id` (uuid, primary key)
   - `request_id` (string, unique)
   - `spec_name` (string) and `spec_version` (integer/hash) to track schema changes
   - `status` (`:pending | :running | :paused | :completed | :failed`)
   - `input` (jsonb) – normalized engine input
   - `context` (jsonb) – runtime context (request_id, metadata)
   - `results` (jsonb) – map of completed step outputs
   - `audit_trail` (jsonb) – engine-generated audit entries
   - `last_step_id` (string) and `last_attempt` (integer)
   - `error` (jsonb, nullable) – last failure surface
   - `inserted_at` / `updated_at`

3. **Extend the workflow engine with a persistence adapter.**
   - Define `Synapse.Workflow.Persistence` behaviour (`save_snapshot/1`,
     `load_snapshot/1`, `mark_complete/2`, `purge/2`).
   - Provide a Postgres implementation that uses the Repo + table above.
   - Engine accepts an optional `:persistence` module in `execute/2`; when
     provided, it writes a snapshot after each successful step and after a
     terminal failure.

4. **Expose runtime helpers.** Add `Synapse.Workflow.Persistence.Supervisor`
   under `Synapse.Runtime` to start the Repo + any needed ETS caches. Provide a
   simple `Synapse.Workflow.Runtime.resume(request_id, opts)` that loads the
   snapshot and returns a struct the coordinator can pass back into the engine
   once resume semantics are implemented.

5. **Testing & tooling.** Add factories for workflow snapshots, integration
   tests ensuring snapshots persist across restarts, and documentation for
   configuring Postgres locally (mix tasks, env vars).

Phase 1 explicitly limits scope to single-runtime usage: no distributed locks,
no saga rollback coordination, and no cross-runtime signaling. Those topics are
deferred to ADR-0010.

## Consequences

* New dependencies (Ecto/Postgrex) and a Repo supervision tree become part of
  the runtime kernel; adapters must configure database credentials.
* Engine callers can opt into persistence incrementally by passing the
  persistence adapter; existing ephemeral workflows continue working.
* Postgres now holds sensitive workflow input/LLM prompts—requires security
  review (encryption at rest, data retention policies).
* Adds operational overhead (migrations, DB availability). Phase 1 keeps it
  simple but still requires staging/prod database instances.

## Alternatives Considered

1. **ETS/DETS snapshots.** Simpler but volatile; fails the durability requirement.
2. **Event-sourcing via Signal Router.** Would reuse existing infrastructure but
   complicates replay semantics and couples persistence with the bus.
3. **External workflow DB (Temporal).** Overkill for Phase 1; alien tech stack.

## Related Work

* ADR-0004 (Workflow Engine) – producer of the state we persist.
* ADR-0002 (Runtime Kernel) – will supervise the Repo/persistence processes.
* ADR-0010 (upcoming) – Phase 2 resilience/distributed saga extensions.
