# Stage 1 – MVP Multi-Agent Review Loop

This folder captures the complete design, backlog, and test plan for the Stage 1 release of our Synapse multi-agent framework. All content here is source-of-truth for the initial implementation; any future iterations should extend these documents, not replace them.

## Document Map

| File | Purpose |
| --- | --- |
| `architecture.md` | System topology, signal flows, directives, and state transitions. |
| `agents.md` | Responsibilities, schemas, decision logic, and directives for each agent. |
| `actions.md` | Jido actions (security & performance toolkits) with schema contracts. |
| `signals.md` | Canonical signal types, payload schemas, and routing patterns. |
| `testing.md` | TDD matrix, coverage goals, fixture design, and CI hooks. |
| `backlog.md` | Task-level breakdown (mirrors TDD steps) with acceptance criteria. |

## Scope Reminder

- Two specialist agents (`SecurityAgent`, `PerformanceAgent`) orchestrated by `CoordinatorAgent`.
- `Jido.Signal.Bus` drives all coordination; no direct function piping allowed.
- Specialists maintain review history, learned patterns, and scar tissue in their state.
- Coordinator synthesizes results into a `review.summary` signal.
- Everything ships with failing tests first (per `testing.md`) and must pass `mix precommit`.

## Reading Order

1. `architecture.md` – understand the big picture.
2. `agents.md` & `actions.md` – what we need to implement.
3. `signals.md` – guarantees expected by orchestrators and specialists.
4. `testing.md` – how we prove it works.
5. `backlog.md` – concrete tasks for the iteration.

---

Keep this directory in lockstep with implementation. Any divergence between docs and code should block the pipeline.***
