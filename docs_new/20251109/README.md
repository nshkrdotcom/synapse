# Synapse Orchestrator Roadmap – Workflow-First Direction
_2025-11-09_

## Context

The workflow engine (ADR-0004) now powers every orchestrator entry point:

- Chain/Critic/Specialist workflows wrap actions with telemetry, retries, and Postgres snapshots (ADR-0009).
- Coordinator fast-path + deep-review flows call their own specs, so summaries persist across restarts.
- Orchestrator runtimes (`Synapse.Orchestrator.Runtime` → `RunConfig`) now execute declarative specs with `on_error: :continue`, propagating request IDs from incoming signals via `DynamicAgent`.

With the plumbing unified, we need a post-migration plan that:

1. **Hardens persistence + recovery** (pause/resume, replay, ops visibility).
2. **Raises the level of abstraction** for orchestrator configs (mini-DSL, reusable patterns).
3. **Exposes telemetry for operators** (dashboards, stuck workflow detection).

## Phase 1 – Operational Readiness (Now → Q1)

| Track | Goals | Notes |
| --- | --- | --- |
| Persistence Ops | expose `workflow_executions` via `Synapse.Workflow.Persistence` API, add indexes (request_id, spec_name, status) | needed for dashboards + cleanup jobs |
| Replay & Resume | implement `Synapse.Workflow.Engine.resume/2` that ingests a persisted snapshot and restarts pending steps | depends on ADR-0009 snapshot schema already storing `results` + `audit_trail` |
| Incident Playbooks | add CLI / Phoenix endpoints to query stuck workflows (`status != completed` for > N minutes) | leverages deterministic request IDs on orchestrators & specialists |

Deliverables:
- `mix synapse.workflow.list --status failed` CLI.
- `WorkflowExecutionLive` (LiveView) showing active/stuck snapshots.
- ADR-0011: Pause/Resume semantics + resume API contract.

## Phase 2 – Declarative Orchestrator DSL (Q1 → Q2)

| Problem | Plan |
| --- | --- |
| Config verbosity | Introduce `Synapse.Orchestrator.Spec` with helpers like `pipeline [:security_suite, :performance_suite]` rather than raw action lists. |
| Result builders copy/paste | Provide built-in combinators: `Workflow.Result.combine_findings/1`, `Workflow.Result.summary/2`. |
| Manual context wiring | Support `context_fn/1` per config to inject request_id / metadata without editing `DynamicAgent`. |

Action items:
1. Draft ADR-0012 defining orchestrator spec DSL (steps, error handling, signal bindings).
2. Implement compiler that turns DSL into the existing `RunConfig` spec structure.
3. Update `priv/orchestrator_agents.exs` to the new DSL + add regression tests.

## Phase 3 – Telemetry & Insights (Q2)

- Emit `[:synapse, :workflow, :orchestrator, :summary]` events whenever orchestrator configs finish, tagged with `config_id`, `status`, `duration_ms`, `emitted?`.
- Ship Grafana/Loki dashboards powered by the telemetry metrics + `workflow_executions` counts.
- Integrate with incident tooling: send stuck-workflow alerts to PagerDuty / Slack once a snapshot misses SLA.

## Long-Term Vision

- **Adaptive reroute:** Use persisted findings to bias which specialists run (e.g., skip perf agent when history shows no hotspots for a repo).
- **Cross-runtime replay:** Archive snapshots to S3/GCS and allow resuming in fresh runtimes (multi-region failover).
- **Agent marketplace:** With DSL + workflows standardized, third-party specialists can register specs and get orchestrated without custom code.

## Next Actions

1. Write ADR-0011 (Pause/Resume semantics + resume API contract).
2. Implement workflow catalog CLI + Phoenix page.
3. Begin DSL spike for orchestrator configs (Phase 2).  
4. Coordinate with ops to define SLOs for `workflow_executions` (e.g., < 2m from request to summary for fast-path).

This document lives alongside the 2025-11-08 roadmap and should be updated as each phase lands. EOF
