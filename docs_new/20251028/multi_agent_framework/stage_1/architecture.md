# Stage 1 Architecture

## Topology Overview

```
┌────────────────────┐       ┌──────────────────────────┐
│ review.request     │       │ review.summary           │
│ (Jido.Signal.Bus)  │       │ (Jido.Signal.Bus)        │
└────────┬───────────┘       └────────┬────────────────┘
         │                            ▲
         ▼                            │
┌────────────────────┐                │
│ CoordinatorAgent   │────────────┐   │
│ (stateful)         │            │   │
└────────┬───────────┘            │   │
         │ directives             │   │
         ▼                        │   │
┌────────────────────┐            │   │
│ Spawn / Enqueue    │            │   │
│ directives         │            │   │
└────────┬───────────┘            │   │
         │                        │   │
   ┌─────┴────┐              ┌────┴────┐
   │Security  │              │Performance│
   │Agent     │              │Agent      │
   └────┬─────┘              └────┬──────┘
        │ review.result           │ review.result
        └─────────────────────────┴──────────────────┘
```

## Core Responsibilities

| Component | Responsibility |
| --- | --- |
| `CoordinatorAgent` | Classify review intent, spawn specialists, issue instructions, listen for results, synthesize summary, track orchestration state. |
| `SecurityAgent` | Execute security-focused checks, maintain learned patterns, record scar tissue, emit structured findings. |
| `PerformanceAgent` | Execute performance-focused checks, maintain learned patterns, record scar tissue, emit structured findings. |
| `Jido.Signal.Bus` | Transport `review.*` signals, enforce routing rules, provide replay hooks for tests. |

## Execution Sequence (Happy Path)

1. **Request** – Upstream publisher emits `review.request` with diff metadata, intent, and constraints.
2. **Classification** – Coordinator inspects request (size, risk flags, urgency) to pick a path:
   - `fast_path` → run minimal checks (if small/no risk).
   - `deep_review` → run full specialist suite.
3. **Preparation** – Coordinator ensures specialists are alive (`Directive.Spawn`) and enqueues instructions (`Directive.Enqueue`) scoped to the request.
4. **Specialist Execution** – Each specialist runs its Jido action pipeline (`Jido.Exec.run/3` under the hood), updates state, and emits `review.result`.
5. **Synthesis** – Coordinator aggregates specialist results, computes severity summary, and emits `review.summary`.
6. **State Persistence** – Agents append review history, update learned pattern counts, and store scar tissue entries when recommended.

## State Model Snapshots

### CoordinatorAgent

```elixir
%{
  review_count: integer(),
  active_reviews: %{review_id() => %{status: :awaiting | :complete, results: [result()]}}
}
```

### Specialist Agents

```elixir
%{
  review_history: [%{review_id: _, timestamp: _, issues_found: non_neg_integer()}],
  learned_patterns: [%{pattern: binary(), count: non_neg_integer(), examples: list()}],
  scar_tissue: [%{pattern: binary(), mitigation: binary(), timestamp: DateTime.t()}]
}
```

## Directives & Signals

| Trigger | Directive / Signal | Purpose |
| --- | --- | --- |
| Coordinator initialization | `Directive.RegisterAction` | Ensure coordinator can issue synthesis + classification actions. |
| `review.request` | `Directive.Spawn` | Guarantee specialists are running. |
| `review.request` | `Directive.Enqueue` | Queue specialist-specific instruction bundles. |
| Specialist completion | `review.result` signal | Async delivery of findings to coordinator (and auditors). |
| Aggregation complete | `review.summary` signal | Final, downstream-consumable review artifact. |

Detailed schemas are defined in `signals.md`.

## Failure Handling

| Failure | Strategy |
| --- | --- |
| Specialist crashes mid-review | Coordinator catches `Directive.Spawn` failure, requeues work (max 1 retry), logs scar tissue entry. |
| No specialists respond | Coordinator emits `review.summary` with `status: :failed`, raises `review.escalate` signal for HITL (future Phase). |
| Action validation errors | Specialists emit result with `status: :error` and include `validation_errors` array; coordinator records degraded summary. |

## Observability Hooks

- `Jido.Signal.Bus` telemetry (`[:jido, :signal, :publish]` and `[:jido, :signal, :dispatch]`) is enabled.
- Each agent logs directive application at `:debug` and emits `review.history` signals when `MIX_ENV=dev`.
- Tests use bus snapshots (`Jido.Signal.Bus.snapshot_create/2`) to inspect sequences without production subscribers.

---

This architecture is intentionally minimal but future-proof: every component communicates via signals and directives, allowing us to expand into marketplace matching, negotiation, and shared learning (Stage 2) without refactoring the Stage 1 core.***
