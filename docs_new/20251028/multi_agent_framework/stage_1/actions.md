# Stage 1 Actions

All actions live in `lib/synapse/actions/<domain>/`. Namespaces shown below assume we mirror the folder layout.

## Common Conventions

- Every action uses `use Jido.Action`.
- Schemas validate payloads early. No optional params unless necessary.
- Actions return `{:ok, result}` with consistent structure; errors use `Jido.Action.Error.execution_error/2`.
- Each action has a matching `*_test.exs` file under `test/synapse/actions/<domain>/`.
- Actions emit telemetry (`[:synapse, :action, :complete]`) via standard `Jido.Action` hooks.

---

## Review Classification & Synthesis (Coordinator Toolkit)

### `Synapse.Actions.Review.ClassifyChange`

| Field | Type | Description |
| --- | --- | --- |
| `files_changed` | `non_neg_integer` | Count of files modified. |
| `labels` | `list(string)` | Labels or tags on the change. |
| `intent` | `string` | e.g. `"hotfix"`, `"feature"`. |
| `risk_factor` | `float` | Optional (default 0.0). |

Returns:

```elixir
%{review_id: String.t(), path: :fast_path | :deep_review, rationale: String.t()}
```

### `Synapse.Actions.Review.GenerateSummary`

| Field | Type | Description |
| --- | --- | --- |
| `review_id` | `string` | Correlates summary with request. |
| `findings` | `list(map)` | Combined findings from specialists. |
| `metadata` | `map` | Additional context (timings, path). |

Returns summary payload used in `review.summary` signal:

```elixir
%{
  review_id: String.t(),
  status: :complete | :failed,
  severity: :none | :low | :medium | :high,
  findings: list(),
  recommendations: list(),
  escalations: list()
}
```

---

## Security Actions

### `Synapse.Actions.Security.CheckSQLInjection`

Inputs:

| Field | Type | Description |
| --- | --- | --- |
| `diff` | `string` | Unified diff snippet. |
| `files` | `list(string)` | Files touched (for context). |
| `metadata` | `map` | Additional info (language, framework). |

Output:

```elixir
%{
  findings: [
    %{type: :sql_injection, file: String.t(), severity: :high | :medium | :low, summary: String.t()}
  ],
  confidence: float(),
  recommended_actions: list(String.t())
}
```

### `Synapse.Actions.Security.CheckXSS`

Same input shape as above. Detects HTML/JS templating risks.

### `Synapse.Actions.Security.CheckAuthIssues`

Focus on authentication & authorization regressions, e.g., removed guards.

Common helper module `Synapse.Actions.Security.Detectors` can assist with shared heuristics.

---

## Performance Actions

### `Synapse.Actions.Performance.CheckComplexity`

Inputs:

| Field | Type |
| --- | --- |
| `diff` | `string` |
| `language` | `string` |
| `thresholds` | `map` (defaults) |

Outputs complexity score and flagged hotspots.

### `Synapse.Actions.Performance.CheckMemoryUsage`

Targets obvious allocations/regressions (e.g., use of `Enum.to_list` on streams).

### `Synapse.Actions.Performance.ProfileHotPath`

Runs synthetic benchmark or heuristic scoring based on changed functions.

---

## Result Normalization

All specialist actions should wrap raw outputs into the shared contract used by agents:

```elixir
%{
  agent: "security_specialist" | "performance_specialist",
  review_id: String.t(),
  confidence: float(),
  findings: list(%{type: atom(), file: String.t(), severity: atom(), summary: String.t()}),
  should_escalate: boolean(),
  metadata: %{runtime_ms: non_neg_integer()}
}
```

Agents can populate `review_id` and `metadata` before emitting signals.

---

## Test Expectations

- **Schema Tests** – invalid payloads must return `{:error, %Jido.Action.Error{type: :validation_error}}`.
- **Happy Path Tests** – assert key findings, severity calculations, and confidence ranges.
- **Edge Cases** – ensure actions handle empty diffs, unsupported languages, and malformed metadata gracefully.

Refer to `testing.md` for the complete test matrix.***
