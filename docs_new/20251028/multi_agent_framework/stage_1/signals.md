# Stage 1 Signal Contracts

All signals follow CloudEvents v1.0.2 via `Jido.Signal`. Attribute names below map to the resulting struct fields.

## 1. `review.request`

| Attribute | Type | Description |
| --- | --- | --- |
| `type` | `"review.request"` | Signal classification. |
| `source` | `"/synapse/reviews"` | Origin of the request. |
| `id` | UUID | Unique per request. |
| `data` | map | See payload schema. |

Payload (`data`):

```elixir
%{
  review_id: String.t(),
  diff: String.t(),
  files_changed: non_neg_integer(),
  labels: [String.t()],
  intent: String.t(),
  risk_factor: float(),
  metadata: %{
    author: String.t(),
    branch: String.t(),
    repo: String.t(),
    timestamp: DateTime.t()
  }
}
```

Routing:
- Sent to `CoordinatorAgent` via `Jido.Signal.Bus`.
- Coordinator snapshots payload into `active_reviews`.

## 2. `review.result`

Emitted by specialist agents.

Attributes:

| Attribute | Type | Notes |
| --- | --- | --- |
| `type` | `"review.result"` | |
| `source` | `"/synapse/agents/<agent_name>"` | e.g., `/synapse/agents/security_specialist`. |
| `subject` | `"jido://review/<review_id>"` | For correlation. |

Payload:

```elixir
%{
  review_id: String.t(),
  agent: "security_specialist" | "performance_specialist",
  confidence: float(),
  findings: [
    %{
      type: atom(),
      severity: :none | :low | :medium | :high,
      file: String.t(),
      summary: String.t(),
      recommendation: String.t() | nil
    }
  ],
  should_escalate: boolean(),
  metadata: %{
    runtime_ms: non_neg_integer(),
    path: :fast_path | :deep_review,
    actions_run: [module()]
  }
}
```

Coordinator listens on `subject` and aggregates results until all expected specialists respond.

## 3. `review.summary`

Emitted by `CoordinatorAgent`.

Attributes:

| Attribute | Type |
| --- | --- |
| `type` | `"review.summary"` |
| `source` | `"/synapse/agents/coordinator"` |
| `subject` | `"jido://review/<review_id>"` |

Payload:

```elixir
%{
  review_id: String.t(),
  status: :complete | :failed,
  severity: :none | :low | :medium | :high,
  findings: [
    %{
      type: atom(),
      severity: atom(),
      file: String.t(),
      summary: String.t(),
      agent: String.t()
    }
  ],
  recommendations: [String.t()],
  escalations: [String.t()],
  metadata: %{
    decision_path: :fast_path | :deep_review,
    specialists_resolved: [String.t()],
    duration_ms: non_neg_integer()
  }
}
```

Downstream consumers (Slack bots, dashboards, gating jobs) subscribe to this signal.

## 4. `review.history` (optional dev trace)

Agents can emit this at `:debug` level in non-prod environments for observability. Not required in Stage 1 tests but useful locally.

Payload:

```elixir
%{
  review_id: String.t(),
  agent: String.t(),
  history: agent_state.review_history
}
```

## Signal Routing Rules

| Pattern | Target |
| --- | --- |
| `"review.request"` | Coordinator queue (`Directive.Enqueue`). |
| `"review.result"` | Coordinator aggregator; optionally auditing tools. |
| `"review.summary"` | External publishers (`Synapse.SignalPublisher`). |

All routes are declared in coordinator and specialist agent modules via `routes/0` or `start_link` opts. See `architecture.md` for call graph and `testing.md` for snapshot usage.

## Validation & Error Handling

- Signals must validate via `Jido.Signal.new!/3` inside tests (fail fast).
- Invalid payloads should be rejected before hitting bus; use action schemas.
- Missing responses within timeout trigger coordinator to emit summary with `status: :failed` and `escalations: ["No response from <agent>"]`.

---

Keep this contract stable. Any changes require updating tests, agents, and this file simultaneously.***
