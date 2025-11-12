# Stage 1 Agents

## CoordinatorAgent

### Responsibility

- Consume `review.request` signals.
- Determine review path (`:fast_path` vs `:deep_review`).
- Ensure specialist agents are alive.
- Enqueue specialist instructions via directives.
- Collect `review.result` signals, store interim state.
- Emit consolidated `review.summary`.

### Schema

```elixir
use Jido.Agent,
  name: "coordinator",
  description: "Routes review work to specialists and synthesizes results",
  actions: [
    Synapse.Actions.Review.ClassifyChange,
    Synapse.Actions.Review.GenerateSummary
  ],
  schema: [
    review_count: [type: :integer, default: 0],
    active_reviews: [
      type: {:map, :map},
      default: %{},
      doc: "ReviewID => %{status: atom(), results: [result()]}"
    ]
  ]
```

### Signals & Directives

| Trigger | Response |
| --- | --- |
| `review.request` | `Directive.Spawn` specialists (idempotent). |
| `review.request` | `Directive.Enqueue` instructions for each specialist. |
| `review.result` | Update `active_reviews`, check completion, possibly emit `review.summary`. |
| `review.summary` (self-emitted) | Increment `review_count`, cleanup `active_reviews`. |

### Decision Logic

```elixir
def classify(review) do
  cond do
    review.files_changed > 50 -> :deep_review
    Enum.any?(review.labels, &(&1 in ["security", "performance"])) -> :deep_review
    review.intent == "hotfix" -> :fast_path
    true -> :fast_path
  end
end
```

### State Updates

- `active_reviews[review_id]` holds `%{status, pending_agents, results}`.
- After summary emission, entry is removed.
- `review_count` increments for metrics.

---

## SecurityAgent

### Responsibility

- Run security-focused checks for a single review.
- Track patterns of recurring issues.
- Record scar tissue for failed mitigations.
- Emit structured findings via `review.result`.

### Schema

```elixir
use Jido.Agent,
  name: "security_specialist",
  description: "Finds security risks in code diffs",
  actions: [
    Synapse.Actions.Security.CheckSQLInjection,
    Synapse.Actions.Security.CheckXSS,
    Synapse.Actions.Security.CheckAuthIssues
  ],
  schema: [
    review_history: [type: {:list, :map}, default: []],
    learned_patterns: [type: {:list, :map}, default: []],
    scar_tissue: [type: {:list, :map}, default: []]
  ]
```

### Directive Handling

- Receives `Directive.Enqueue` with payload `%{review_id, files, metadata}`.
- Runs each listed action in order (using `Jido.Exec.run/3`).
- Calls `record_history/2`, `learn_from_correction/2` as needed.

### Result Structure

```elixir
%{
  review_id: String.t(),
  agent: "security_specialist",
  confidence: float(),
  findings: [
    %{type: :sql_injection, file: "lib/foo.ex", severity: :high, summary: "..."}
  ],
  should_escalate: boolean(),
  metadata: %{runtime_ms: non_neg_integer()}
}
```

---

## PerformanceAgent

### Responsibility

- Detect performance regressions and hotspots.
- Track patterns (e.g., repeated N+1 queries).
- Emit results consistent with security agent for easy synthesis.

### Schema

```elixir
use Jido.Agent,
  name: "performance_specialist",
  description: "Evaluates performance implications of changes",
  actions: [
    Synapse.Actions.Performance.CheckComplexity,
    Synapse.Actions.Performance.CheckMemoryUsage,
    Synapse.Actions.Performance.ProfileHotPath
  ],
  schema: [
    review_history: [type: {:list, :map}, default: []],
    learned_patterns: [type: {:list, :map}, default: []],
    scar_tissue: [type: {:list, :map}, default: []]
  ]
```

### Result Structure

```elixir
%{
  review_id: String.t(),
  agent: "performance_specialist",
  confidence: float(),
  findings: [
    %{type: :cpu_hotspot, file: "lib/bar.ex", severity: :medium, summary: "..."}
  ],
  should_escalate: boolean(),
  metadata: %{runtime_ms: non_neg_integer()}
}
```

---

## Shared Behaviors

- Both specialists expose helper functions:
  - `record_history(agent, review_metadata)` (keep last 100 entries).
  - `learn_from_correction(agent, pattern_payload)` (update or create pattern).
  - `record_failure(agent, failure_payload)` (append to scar tissue with timestamp).
- All agents log at `:debug` when receiving directives/signals; `:info` when emitting results/summaries.
- All agents must survive being spawned multiple times (`start_link/1` idempotent via `Registry`).

---

## Non-Goals (Stage 1)

- No marketplace enrollment.
- No multi-level agent hierarchy.
- No negotiation signals (`review.conflict`) yet.
- No persistent storage beyond in-memory state (future phases may sync to DB).

---

Keep this file updated alongside code. Any drift (e.g., new actions, schema changes) must be reflected here before merging.***
