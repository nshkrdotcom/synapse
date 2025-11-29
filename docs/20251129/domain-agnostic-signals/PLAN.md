# Domain-Agnostic Signal Layer

**Status:** Proposal
**Created:** 2025-11-29
**Goal:** Transform Synapse from a code-review-specific runtime into a general-purpose multi-agent orchestration framework

---

## Problem Statement

Synapse's core primitives (signal bus, workflow engine, agent lifecycle, action framework) are domain-agnostic, but the signal layer is hardcoded for code review:

- Signal topics are a closed set: `:review_request`, `:review_result`, `:review_summary`, `:specialist_ready`
- Signal schemas contain review-specific fields: `review_id`, `diff`, `files_changed`
- Orchestrator logic matches against hardcoded signal types
- State keys use review terminology: `reviews`, `fast_path`, `deep_review`

Users cannot define custom domains (document processing, customer support, data pipelines) without modifying core Synapse modules.

---

## Current Architecture

### Signal Registry (`lib/synapse/signal.ex`)

```elixir
@topics %{
  review_request: %{type: "review.request", schema: ReviewRequest},
  review_result: %{type: "review.result", schema: ReviewResult},
  review_summary: %{type: "review.summary", schema: ReviewSummary},
  specialist_ready: %{type: "review.specialist_ready", schema: SpecialistReady}
}
```

Compile-time, closed set. Adding a new topic requires code changes.

### Signal Schemas (`lib/synapse/signal/review_*.ex`)

Four separate modules with hardcoded fields:

| Module | Review-Specific Fields |
|--------|------------------------|
| `ReviewRequest` | `review_id`, `diff`, `files_changed`, `labels`, `language` |
| `ReviewResult` | `review_id`, `agent`, `findings`, `should_escalate` |
| `ReviewSummary` | `review_id`, `severity`, `findings`, `recommendations` |
| `SpecialistReady` | `specialist_id`, `capabilities` |

### Orchestrator Signal Matching (`lib/synapse/orchestrator/actions/run_config.ex:239-244`)

```elixir
signal.type == Signal.type(:review_request) ->
  handle_orchestrator_request(...)

signal.type == Signal.type(:review_result) ->
  handle_orchestrator_result(...)
```

Hardcoded dispatch based on review signal types.

### Orchestrator State (`run_config.ex:24-26`)

```elixir
@orchestrator_defaults %{
  reviews: %{},
  stats: %{total: 0, fast_path: 0, deep_review: 0, completed: 0}
}
```

### Agent Config Validation (`lib/synapse/orchestrator/agent_config.ex:258-270`)

```elixir
defp normalize_topic(topic) when is_atom(topic) do
  if topic in Signal.topics() do  # validates against hardcoded list
    {:ok, topic}
  else
    {:error, "unknown signal topic #{inspect(topic)}"}
  end
end
```

---

## Implementation Plan: Concurrent Work Streams

### Dependency Analysis

Almost all changes depend on the Signal Registry being updated first:

- `signal_router.ex` calls `Signal.topics()` and `Signal.type()`
- `agent_config.ex` validates topics against `Signal.topics()`
- `run_config.ex` calls `Signal.type(:review_request)`
- Domain migration moves files that `signal.ex` references

**Result:** Phase 1 must complete before Phase 2 streams can begin.

---

## Phase 1: Signal Registry Foundation (Sequential)

**Must complete before any other work begins.**

### Files

| File | Change | Description |
|------|--------|-------------|
| `lib/synapse/signal/registry.ex` | NEW | Runtime topic registry with ETS backend |
| `lib/synapse/signal.ex` | MODIFY | Delegate to registry, remove hardcoded `@topics` |
| `lib/synapse/signal/schema.ex` | MODIFY | Support inline schema definitions |
| `config/config.exs` | MODIFY | Add `:topics` configuration |

### New: `lib/synapse/signal/registry.ex`

```elixir
defmodule Synapse.Signal.Registry do
  @moduledoc """
  Runtime registry for signal topics and their schemas.

  Topics can be defined via application config or registered at runtime.
  Uses ETS for fast concurrent reads.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts \\ [])
  def register_topic(topic, config)
  def unregister_topic(topic)
  def get_topic(topic)
  def list_topics()
  def type(topic)
  def schema(topic)
  def validate!(topic, payload)
end
```

### Modified: `lib/synapse/signal.ex`

```elixir
defmodule Synapse.Signal do
  @moduledoc """
  Canonical registry of signal topics and their schemas.
  Delegates to Synapse.Signal.Registry for runtime topic management.
  """

  alias Synapse.Signal.Registry

  @type topic :: atom()

  defdelegate type(topic), to: Registry
  defdelegate topics(), to: Registry, as: :list_topics
  defdelegate validate!(topic, payload), to: Registry
  defdelegate topic_from_type(type_string), to: Registry
  defdelegate register_topic(topic, config), to: Registry
end
```

### Config: `config/config.exs`

```elixir
config :synapse, Synapse.Signal.Registry,
  topics: [
    task_request: [
      type: "synapse.task.request",
      schema: [
        task_id: [type: :string, required: true],
        payload: [type: :map, default: %{}],
        metadata: [type: :map, default: %{}],
        labels: [type: {:list, :string}, default: []],
        priority: [type: {:in, [:low, :normal, :high, :urgent]}, default: :normal]
      ]
    ],
    task_result: [
      type: "synapse.task.result",
      schema: [
        task_id: [type: :string, required: true],
        agent: [type: :string, required: true],
        status: [type: {:in, [:ok, :error, :partial]}, default: :ok],
        output: [type: :map, default: %{}],
        metadata: [type: :map, default: %{}]
      ]
    ],
    task_summary: [
      type: "synapse.task.summary",
      schema: [
        task_id: [type: :string, required: true],
        status: [type: :atom, default: :complete],
        results: [type: {:list, :map}, default: []],
        metadata: [type: :map, default: %{}]
      ]
    ],
    worker_ready: [
      type: "synapse.worker.ready",
      schema: [
        worker_id: [type: :string, required: true],
        capabilities: [type: {:list, :string}, default: []]
      ]
    ]
  ]
```

### Deliverables

- [ ] `Synapse.Signal.Registry` GenServer with ETS table
- [ ] Config loading on startup
- [ ] `register_topic/2` runtime API
- [ ] `Synapse.Signal` delegating to registry
- [ ] Inline schema validation (no separate module required)
- [ ] Tests for registry CRUD operations

---

## Phase 2: Parallel Consumer Updates (3 Concurrent Streams)

**Can run in parallel after Phase 1 completes. No file overlap between streams.**

```
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│ Stream 2A            │  │ Stream 2B            │  │ Stream 2C            │
│                      │  │                      │  │                      │
│ signal_router.ex     │  │ agent_config.ex      │  │ run_config.ex        │
│                      │  │                      │  │                      │
└──────────────────────┘  └──────────────────────┘  └──────────────────────┘
```

---

### Stream 2A: Signal Router

**File:** `lib/synapse/signal_router.ex`

#### Changes

1. Replace static topic index with dynamic registry lookup
2. Subscribe to topics from registry on init
3. Handle new topic registrations at runtime (optional)

#### Current Code

```elixir
# Line 185
topic_index: Map.new(Signal.topics(), &{&1, MapSet.new()})

# Lines 325-338
defp subscribe_to_topics(state) do
  bus_subscriptions =
    Enum.reduce(Signal.topics(), %{}, fn topic, acc ->
      # ...
    end)
end
```

#### New Code

```elixir
# Line 185 - unchanged, Signal.topics() now reads from registry
topic_index: Map.new(Signal.topics(), &{&1, MapSet.new()})

# Add handler for runtime topic registration (optional enhancement)
def handle_info({:topic_registered, topic}, state) do
  # Subscribe to new topic, update index
end
```

#### Deliverables

- [ ] Router uses `Signal.topics()` (already dynamic after Phase 1)
- [ ] Tests verify router works with config-defined topics
- [ ] (Optional) Runtime topic subscription on registration

---

### Stream 2B: Agent Config

**File:** `lib/synapse/orchestrator/agent_config.ex`

#### Changes

1. Add `roles` map to signals schema
2. Update `validate_signals/1` to parse roles
3. Update `normalize_topic/1` to validate against registry (already works after Phase 1)

#### Current Signals Schema

```elixir
signals: %{
  subscribes: [:review_request],
  emits: [:review_result]
}
```

#### New Signals Schema

```elixir
signals: %{
  subscribes: [:task_request, :task_result],
  emits: [:task_summary],
  roles: %{
    request: :task_request,    # which topic triggers new work
    result: :task_result,      # which topic carries worker results
    summary: :task_summary     # what to emit on completion
  }
}
```

#### Code Changes

```elixir
# Update validate_signals/1
def validate_signals(%{} = value) do
  with {:ok, subscribes} <- fetch_signal_list(value, :subscribes, required?: true),
       {:ok, emits} <- fetch_signal_list(value, :emits, required?: false),
       {:ok, roles} <- fetch_signal_roles(value, subscribes, emits) do
    {:ok, %{subscribes: subscribes, emits: emits, roles: roles}}
  end
end

defp fetch_signal_roles(map, subscribes, emits) do
  roles = Map.get(map, :roles, %{})

  default_roles = infer_default_roles(subscribes, emits)
  merged = Map.merge(default_roles, roles)

  # Validate role topics exist in registry
  with :ok <- validate_role_topics(merged) do
    {:ok, merged}
  end
end

defp infer_default_roles(subscribes, emits) do
  %{
    request: Enum.find(subscribes, &String.contains?(to_string(&1), "request")),
    result: Enum.find(subscribes, &String.contains?(to_string(&1), "result")),
    summary: List.first(emits)
  }
end
```

#### Deliverables

- [ ] `roles` map in signals config
- [ ] Default role inference from topic names
- [ ] Role topic validation
- [ ] Backward compatibility (roles optional)
- [ ] Tests for role parsing and defaults

---

### Stream 2C: Orchestrator Run Config

**File:** `lib/synapse/orchestrator/actions/run_config.ex`

#### Changes

1. Read topic roles from `config.signals.roles` instead of hardcoding
2. Rename state keys: `reviews` → `tasks`
3. Support `initial_state` from agent config

#### Current Code (Lines 239-247)

```elixir
cond do
  is_nil(signal) ->
    {:ok, %{state: state}}

  signal.type == Signal.type(:review_request) ->
    handle_orchestrator_request(...)

  signal.type == Signal.type(:review_result) ->
    handle_orchestrator_result(...)

  true ->
    {:ok, %{state: state}}
end
```

#### New Code

```elixir
defp run_orchestrator(config, params) do
  router = Map.get(params, :_router)
  state = Map.get(params, :_state) || initial_state(config)
  signal = Map.get(params, :_signal)
  emits = Map.get(params, :_emits, config.signals.emits || [])
  orchestration = Map.get(config, :orchestration) || %{}

  roles = Map.get(config.signals, :roles, default_roles())
  request_type = Signal.type(roles.request)
  result_type = Signal.type(roles.result)

  cond do
    is_nil(signal) ->
      {:ok, %{state: state}}

    signal.type == request_type ->
      handle_orchestrator_request(config, orchestration, state, signal, router, emits)

    signal.type == result_type ->
      handle_orchestrator_result(config, orchestration, state, signal, router)

    true ->
      {:ok, %{state: state}}
  end
end

defp default_roles do
  %{request: :task_request, result: :task_result, summary: :task_summary}
end

defp initial_state(config) do
  case Map.get(config, :initial_state) do
    nil -> @orchestrator_defaults
    custom when is_map(custom) -> Map.merge(@orchestrator_defaults, custom)
  end
end

# Update default state keys
@orchestrator_defaults %{
  tasks: %{},  # was: reviews
  stats: %{total: 0, routed: 0, completed: 0, failed: 0}
}
```

#### State Key Renames

| Old Key | New Key |
|---------|---------|
| `reviews` | `tasks` |
| `review_id` | `task_id` |
| `review_state` | `task_state` |
| `review_data` | `task_data` |
| `fast_path` | `routed` |
| `deep_review` | `dispatched` |

#### Deliverables

- [ ] Config-driven signal type dispatch
- [ ] `initial_state` support in agent config
- [ ] Generic state key names
- [ ] `default_roles/0` function
- [ ] All internal `review_*` variables renamed to `task_*`
- [ ] Tests updated for new state structure

---

## Phase 3: Domain Migration (Sequential)

**Runs after Phase 2 completes. Moves review-specific code to optional domain.**

### Files

| File | Change | Description |
|------|--------|-------------|
| `lib/synapse/signal/review_request.ex` | MOVE | → `lib/synapse/domains/code_review/signals/review_request.ex` |
| `lib/synapse/signal/review_result.ex` | MOVE | → `lib/synapse/domains/code_review/signals/review_result.ex` |
| `lib/synapse/signal/review_summary.ex` | MOVE | → `lib/synapse/domains/code_review/signals/review_summary.ex` |
| `lib/synapse/signal/specialist_ready.ex` | MOVE | → `lib/synapse/domains/code_review/signals/specialist_ready.ex` |
| `lib/synapse/domains/code_review/domain.ex` | NEW | Domain registration module |
| `priv/orchestrator_agents.exs` | MODIFY | Update to use generic signals |
| `lib/synapse/actions/review/*` | MOVE | → `lib/synapse/domains/code_review/actions/` |
| `lib/synapse/actions/security/*` | MOVE | → `lib/synapse/domains/code_review/actions/` |
| `lib/synapse/actions/performance/*` | MOVE | → `lib/synapse/domains/code_review/actions/` |

### New: `lib/synapse/domains/code_review/domain.ex`

```elixir
defmodule Synapse.Domains.CodeReview do
  @moduledoc """
  Code review domain for Synapse.

  Registers review-specific signal topics and provides
  pre-built actions for security and performance analysis.
  """

  alias Synapse.Signal

  def register do
    Signal.register_topic(:review_request,
      type: "review.request",
      schema: [
        review_id: [type: :string, required: true],
        diff: [type: :string, default: ""],
        files_changed: [type: :integer, default: 0],
        labels: [type: {:list, :string}, default: []],
        intent: [type: :string, default: "feature"],
        risk_factor: [type: :float, default: 0.0],
        files: [type: {:list, :string}, default: []],
        language: [type: :string, default: "elixir"],
        metadata: [type: :map, default: %{}]
      ]
    )

    Signal.register_topic(:review_result,
      type: "review.result",
      schema: [
        review_id: [type: :string, required: true],
        agent: [type: :string, required: true],
        confidence: [type: :float, default: 0.0],
        findings: [type: {:list, :map}, default: []],
        should_escalate: [type: :boolean, default: false],
        metadata: [type: :map, default: %{}]
      ]
    )

    Signal.register_topic(:review_summary,
      type: "review.summary",
      schema: [
        review_id: [type: :string, required: true],
        status: [type: :atom, default: :complete],
        severity: [type: :atom, default: :none],
        findings: [type: {:list, :map}, default: []],
        recommendations: [type: {:list, :any}, default: []],
        escalations: [type: {:list, :string}, default: []],
        metadata: [type: :map, default: %{}]
      ]
    )

    :ok
  end
end
```

### Updated: `priv/orchestrator_agents.exs`

```elixir
# Option A: Use generic signals (recommended for new users)
[
  %{
    id: :security_worker,
    type: :specialist,
    actions: [MyApp.Actions.SecurityCheck],
    signals: %{
      subscribes: [:task_request],
      emits: [:task_result]
    }
  },
  %{
    id: :coordinator,
    type: :orchestrator,
    signals: %{
      subscribes: [:task_request, :task_result],
      emits: [:task_summary],
      roles: %{
        request: :task_request,
        result: :task_result,
        summary: :task_summary
      }
    },
    orchestration: %{...}
  }
]

# Option B: Use code review domain (for existing users)
# Requires: Synapse.Domains.CodeReview.register() in application.ex
[
  %{
    id: :security_specialist,
    type: :specialist,
    actions: [Synapse.Domains.CodeReview.Actions.CheckSQLInjection, ...],
    signals: %{
      subscribes: [:review_request],
      emits: [:review_result]
    }
  },
  # ...
]
```

### Deliverables

- [ ] `Synapse.Domains.CodeReview` module with `register/0`
- [ ] All review signals moved to domain
- [ ] All review/security/performance actions moved to domain
- [ ] Generic `priv/orchestrator_agents.exs` example
- [ ] Code review example in `examples/code_review/`
- [ ] Domain auto-registration option in config

---

## Phase 4: Documentation (Concurrent with Phase 3)

**Can run in parallel with Phase 3. No code file overlap.**

### Files

| File | Change | Description |
|------|--------|-------------|
| `docs/guides/custom-domains.md` | NEW | How to define domain-specific signals |
| `docs/guides/migration-0.2.md` | NEW | Migration from v0.1 review signals |
| `README.md` | MODIFY | Update description, examples |
| `CHANGELOG.md` | MODIFY | Document breaking changes |

### Deliverables

- [ ] Custom domains guide with 3 example domains
- [ ] Migration guide with before/after code samples
- [ ] Updated README reflecting domain-agnostic nature
- [ ] CHANGELOG entry for v0.2.0

---

## Execution Timeline

```
Week 1:
├── Phase 1: Signal Registry (Sequential)
│   ├── Day 1-2: registry.ex implementation
│   ├── Day 3: signal.ex refactor
│   ├── Day 4: config loading
│   └── Day 5: tests + integration

Week 2:
├── Phase 2A: signal_router.ex ──────┐
├── Phase 2B: agent_config.ex ───────┼── (Parallel)
└── Phase 2C: run_config.ex ─────────┘

Week 3:
├── Phase 3: Domain Migration ───────┐
└── Phase 4: Documentation ──────────┴── (Parallel)
```

---

## File Summary by Phase

### Phase 1 (Sequential Foundation)
```
lib/synapse/signal/registry.ex     NEW
lib/synapse/signal.ex              MODIFY
lib/synapse/signal/schema.ex       MODIFY
config/config.exs                  MODIFY
```

### Phase 2A (Signal Router)
```
lib/synapse/signal_router.ex       MODIFY
```

### Phase 2B (Agent Config)
```
lib/synapse/orchestrator/agent_config.ex    MODIFY
```

### Phase 2C (Orchestrator Dispatch)
```
lib/synapse/orchestrator/actions/run_config.ex    MODIFY
```

### Phase 3 (Domain Migration)
```
lib/synapse/signal/review_request.ex        MOVE → domains/code_review/
lib/synapse/signal/review_result.ex         MOVE → domains/code_review/
lib/synapse/signal/review_summary.ex        MOVE → domains/code_review/
lib/synapse/signal/specialist_ready.ex      MOVE → domains/code_review/
lib/synapse/domains/code_review/domain.ex   NEW
lib/synapse/actions/review/*                MOVE → domains/code_review/
lib/synapse/actions/security/*              MOVE → domains/code_review/
lib/synapse/actions/performance/*           MOVE → domains/code_review/
priv/orchestrator_agents.exs                MODIFY
```

### Phase 4 (Documentation)
```
docs/guides/custom-domains.md      NEW
docs/guides/migration-0.2.md       NEW
README.md                          MODIFY
CHANGELOG.md                       MODIFY
```

---

## Success Criteria

1. Users can define custom domains without modifying Synapse source
2. Core Synapse has no code-review-specific terminology
3. Existing code review functionality works via `Synapse.Domains.CodeReview`
4. Signal registration documented with examples for 3+ domains
5. All tests pass with generic signal names
6. Migration path documented and tested

---

## Backwards Compatibility

### Deprecation Strategy

```elixir
# In Synapse.Signal (during transition period)
def type(:review_request) do
  Logger.warning(
    ":review_request is deprecated. " <>
    "Use :task_request or Synapse.Domains.CodeReview.register/0"
  )

  # Check if code review domain is registered
  case Registry.get_topic(:review_request) do
    {:ok, _} -> Registry.type(:review_request)
    :error -> Registry.type(:task_request)
  end
end
```

### Migration Path

1. **v0.1.x → v0.2.0:** Add `Synapse.Domains.CodeReview.register()` to `application.ex`
2. **v0.2.x:** Deprecation warnings for direct `:review_*` usage
3. **v0.3.0:** Remove built-in review signals, require explicit domain registration

---

## Open Questions

1. **Registry persistence:** ETS (fast, in-memory) vs persistent_term (survives restarts)?
2. **Schema hot-reload:** Allow schema updates at runtime?
3. **Namespace conventions:** `synapse.task.request` vs `urn:synapse:task:request`?
4. **Strict validation:** Reject unknown payload fields or pass through?
5. **Domain packaging:** Separate hex packages per domain, or single `synapse_domains` umbrella?
