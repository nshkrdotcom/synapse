# Phase 1: Signal Registry Foundation

**Agent Task:** Implement the dynamic signal registry that replaces hardcoded signal topics.

**Version:** v0.1.1

---

## Required Reading

Before making any changes, read and understand these files completely:

### Core Signal Layer (Read First)
```
lib/synapse/signal.ex
lib/synapse/signal/schema.ex
lib/synapse/signal/review_request.ex
lib/synapse/signal/review_result.ex
lib/synapse/signal/review_summary.ex
lib/synapse/signal/specialist_ready.ex
```

### Consumers of Signal Module (Understand Dependencies)
```
lib/synapse/signal_router.ex
lib/synapse/orchestrator/agent_config.ex
lib/synapse/orchestrator/actions/run_config.ex
```

### Configuration
```
config/config.exs
config/dev.exs
config/test.exs
```

### Existing Tests (Understand Test Patterns)
```
test/synapse/signal_test.exs (if exists)
test/synapse/signal_router_test.exs
test/support/factory.ex
test/support/signal_router_helpers.ex
```

### Plan Document
```
docs/20251129/domain-agnostic-signals/PLAN.md
```

---

## Context

Synapse currently has a hardcoded signal registry in `lib/synapse/signal.ex`:

```elixir
@topics %{
  review_request: %{type: "review.request", schema: ReviewRequest},
  review_result: %{type: "review.result", schema: ReviewResult},
  review_summary: %{type: "review.summary", schema: ReviewSummary},
  specialist_ready: %{type: "review.specialist_ready", schema: SpecialistReady}
}
```

This prevents users from defining custom domains. We need to make the signal registry dynamic and configurable.

---

## Task: TDD Implementation

Use Test-Driven Development. Write tests first, then implement.

### Step 1: Create Signal Registry Tests

Create `test/synapse/signal/registry_test.exs`:

```elixir
defmodule Synapse.Signal.RegistryTest do
  use ExUnit.Case, async: false

  alias Synapse.Signal.Registry

  setup do
    # Start a fresh registry for each test
    # Registry should support being started with a name for testing
    {:ok, pid} = Registry.start_link(name: :"test_registry_#{:rand.uniform(100_000)}")
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{registry: pid}
  end

  describe "start_link/1" do
    test "starts the registry process" do
      assert {:ok, pid} = Registry.start_link(name: :test_start)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "loads topics from config on startup" do
      # Test that configured topics are available after start
    end
  end

  describe "register_topic/2" do
    test "registers a new topic with inline schema", %{registry: registry} do
      assert :ok = Registry.register_topic(registry, :my_topic,
        type: "my.topic",
        schema: [
          id: [type: :string, required: true],
          data: [type: :map, default: %{}]
        ]
      )

      assert {:ok, config} = Registry.get_topic(registry, :my_topic)
      assert config.type == "my.topic"
    end

    test "rejects duplicate topic registration", %{registry: registry} do
      Registry.register_topic(registry, :dupe, type: "dupe", schema: [])
      assert {:error, :already_registered} = Registry.register_topic(registry, :dupe, type: "dupe", schema: [])
    end

    test "validates topic config structure", %{registry: registry} do
      assert {:error, _} = Registry.register_topic(registry, :bad, type: 123, schema: [])
      assert {:error, _} = Registry.register_topic(registry, :bad, schema: []) # missing type
    end
  end

  describe "get_topic/2" do
    test "returns topic config for registered topic", %{registry: registry} do
      Registry.register_topic(registry, :task, type: "task.request", schema: [id: [type: :string, required: true]])
      assert {:ok, %{type: "task.request"}} = Registry.get_topic(registry, :task)
    end

    test "returns error for unknown topic", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_topic(registry, :unknown)
    end
  end

  describe "list_topics/1" do
    test "returns all registered topics", %{registry: registry} do
      Registry.register_topic(registry, :a, type: "a", schema: [])
      Registry.register_topic(registry, :b, type: "b", schema: [])

      topics = Registry.list_topics(registry)
      assert :a in topics
      assert :b in topics
    end
  end

  describe "type/2" do
    test "returns wire type for topic", %{registry: registry} do
      Registry.register_topic(registry, :task, type: "synapse.task", schema: [])
      assert "synapse.task" = Registry.type(registry, :task)
    end

    test "raises for unknown topic", %{registry: registry} do
      assert_raise KeyError, fn -> Registry.type(registry, :unknown) end
    end
  end

  describe "topic_from_type/2" do
    test "resolves wire type to topic atom", %{registry: registry} do
      Registry.register_topic(registry, :task, type: "synapse.task", schema: [])
      assert {:ok, :task} = Registry.topic_from_type(registry, "synapse.task")
    end

    test "returns error for unknown type", %{registry: registry} do
      assert :error = Registry.topic_from_type(registry, "unknown.type")
    end
  end

  describe "validate!/3" do
    test "validates payload against topic schema", %{registry: registry} do
      Registry.register_topic(registry, :task,
        type: "task",
        schema: [
          id: [type: :string, required: true],
          priority: [type: {:in, [:low, :high]}, default: :low]
        ]
      )

      result = Registry.validate!(registry, :task, %{id: "123"})
      assert result.id == "123"
      assert result.priority == :low
    end

    test "raises on invalid payload", %{registry: registry} do
      Registry.register_topic(registry, :task,
        type: "task",
        schema: [id: [type: :string, required: true]]
      )

      assert_raise ArgumentError, fn ->
        Registry.validate!(registry, :task, %{})  # missing required id
      end
    end

    test "raises for unknown topic", %{registry: registry} do
      assert_raise KeyError, fn ->
        Registry.validate!(registry, :unknown, %{})
      end
    end
  end

  describe "unregister_topic/2" do
    test "removes a registered topic", %{registry: registry} do
      Registry.register_topic(registry, :temp, type: "temp", schema: [])
      assert :ok = Registry.unregister_topic(registry, :temp)
      assert {:error, :not_found} = Registry.get_topic(registry, :temp)
    end
  end
end
```

### Step 2: Implement Signal Registry

Create `lib/synapse/signal/registry.ex`:

Requirements:
- Use GenServer with ETS backend for fast concurrent reads
- Support named processes (default: `Synapse.Signal.Registry`)
- Load topics from `Application.get_env(:synapse, Synapse.Signal.Registry, [])[:topics]` on init
- Compile NimbleOptions schemas on registration for fast validation
- Store: `{topic_atom, %{type: String.t(), schema: NimbleOptions.t(), raw_schema: keyword()}}`

API:
```elixir
def start_link(opts \\ [])
def register_topic(registry \\ __MODULE__, topic, config)
def unregister_topic(registry \\ __MODULE__, topic)
def get_topic(registry \\ __MODULE__, topic)
def list_topics(registry \\ __MODULE__)
def type(registry \\ __MODULE__, topic)
def topic_from_type(registry \\ __MODULE__, type_string)
def validate!(registry \\ __MODULE__, topic, payload)
```

### Step 3: Update Signal Module Tests

Update or create `test/synapse/signal_test.exs`:

```elixir
defmodule Synapse.SignalTest do
  use ExUnit.Case, async: false

  alias Synapse.Signal

  # These tests verify Signal delegates to Registry correctly
  # and maintains backward compatibility

  describe "type/1" do
    test "returns wire type for registered topic" do
      # Assuming :task_request is configured
      assert is_binary(Signal.type(:task_request))
    end
  end

  describe "topics/0" do
    test "returns list of all registered topics" do
      topics = Signal.topics()
      assert is_list(topics)
      assert :task_request in topics
    end
  end

  describe "validate!/2" do
    test "validates and returns normalized payload" do
      payload = %{task_id: "123"}
      result = Signal.validate!(:task_request, payload)
      assert result.task_id == "123"
    end
  end

  describe "topic_from_type/1" do
    test "resolves type string to topic" do
      type = Signal.type(:task_request)
      assert {:ok, :task_request} = Signal.topic_from_type(type)
    end
  end

  describe "register_topic/2" do
    test "allows runtime topic registration" do
      topic = :"test_topic_#{:rand.uniform(100_000)}"

      assert :ok = Signal.register_topic(topic,
        type: "test.topic.#{topic}",
        schema: [id: [type: :string, required: true]]
      )

      assert topic in Signal.topics()
    end
  end
end
```

### Step 4: Refactor Signal Module

Update `lib/synapse/signal.ex` to delegate to Registry:

```elixir
defmodule Synapse.Signal do
  @moduledoc """
  Canonical registry of signal topics and their schemas.

  Topics can be defined via application config or registered at runtime.
  Delegates to `Synapse.Signal.Registry` for topic management.

  ## Configuration

      config :synapse, Synapse.Signal.Registry,
        topics: [
          task_request: [
            type: "synapse.task.request",
            schema: [
              task_id: [type: :string, required: true],
              payload: [type: :map, default: %{}]
            ]
          ]
        ]

  ## Runtime Registration

      Synapse.Signal.register_topic(:my_topic,
        type: "my.domain.topic",
        schema: [id: [type: :string, required: true]]
      )
  """

  alias Synapse.Signal.Registry

  @type topic :: atom()

  @doc """
  Returns the wire-format type string for the given topic.
  """
  @spec type(topic()) :: String.t()
  defdelegate type(topic), to: Registry

  @doc """
  Returns all registered topic atoms.
  """
  @spec topics() :: [topic()]
  defdelegate topics(), to: Registry, as: :list_topics

  @doc """
  Validates a payload against the topic's schema.
  Returns normalized map with defaults applied.
  Raises ArgumentError on validation failure.
  """
  @spec validate!(topic(), map()) :: map()
  defdelegate validate!(topic, payload), to: Registry

  @doc """
  Resolves a wire-format type string to its topic atom.
  """
  @spec topic_from_type(String.t()) :: {:ok, topic()} | :error
  defdelegate topic_from_type(type_string), to: Registry

  @doc """
  Registers a new signal topic at runtime.
  """
  @spec register_topic(topic(), keyword()) :: :ok | {:error, term()}
  defdelegate register_topic(topic, config), to: Registry
end
```

### Step 5: Update Signal Schema Module

Update `lib/synapse/signal/schema.ex` to support both module-based and inline schemas:

The existing module-based approach should continue working, but we also need a way to create schemas from keyword lists at runtime.

Add a helper function:

```elixir
@doc """
Creates a validator function from a NimbleOptions schema keyword list.
"""
@spec compile_schema(keyword()) :: (map() -> map())
def compile_schema(schema_def) do
  compiled = NimbleOptions.new!(schema_def)

  fn payload ->
    payload
    |> normalize_payload()
    |> NimbleOptions.validate!(compiled)
    |> Map.new()
  rescue
    e in NimbleOptions.ValidationError ->
      reraise ArgumentError, ["invalid signal payload: ", e.message], __STACKTRACE__
  end
end

defp normalize_payload(payload) when is_map(payload), do: Map.to_list(payload)
defp normalize_payload(payload) when is_list(payload), do: payload
```

### Step 6: Add Configuration

Update `config/config.exs` to define core signal topics:

```elixir
# Signal Registry Configuration
config :synapse, Synapse.Signal.Registry,
  topics: [
    task_request: [
      type: "synapse.task.request",
      schema: [
        task_id: [type: :string, required: true, doc: "Unique task identifier"],
        payload: [type: :map, default: %{}, doc: "Task-specific payload data"],
        metadata: [type: :map, default: %{}, doc: "Arbitrary metadata"],
        labels: [type: {:list, :string}, default: [], doc: "Labels for routing/filtering"],
        priority: [type: {:in, [:low, :normal, :high, :urgent]}, default: :normal, doc: "Task priority"]
      ]
    ],
    task_result: [
      type: "synapse.task.result",
      schema: [
        task_id: [type: :string, required: true, doc: "Task identifier this result belongs to"],
        agent: [type: :string, required: true, doc: "Agent/worker that produced this result"],
        status: [type: {:in, [:ok, :error, :partial]}, default: :ok, doc: "Result status"],
        output: [type: :map, default: %{}, doc: "Result output data"],
        metadata: [type: :map, default: %{}, doc: "Execution metadata"]
      ]
    ],
    task_summary: [
      type: "synapse.task.summary",
      schema: [
        task_id: [type: :string, required: true, doc: "Task identifier"],
        status: [type: :atom, default: :complete, doc: "Overall task status"],
        results: [type: {:list, :map}, default: [], doc: "Aggregated results"],
        metadata: [type: :map, default: %{}, doc: "Summary metadata"]
      ]
    ],
    worker_ready: [
      type: "synapse.worker.ready",
      schema: [
        worker_id: [type: :string, required: true, doc: "Worker identifier"],
        capabilities: [type: {:list, :string}, default: [], doc: "Worker capabilities"]
      ]
    ]
  ]
```

### Step 7: Add Registry to Supervision Tree

Update `lib/synapse/application.ex` to start the Registry:

Find the children list and add Registry before SignalRouter:

```elixir
children = [
  # ... existing children ...
  Synapse.Signal.Registry,  # Add this BEFORE SignalRouter
  # ... SignalRouter and others ...
]
```

### Step 8: Backward Compatibility - Legacy Signal Aliases

To maintain backward compatibility during transition, register the old review signals as aliases. Add to the registry init or create a compatibility module:

```elixir
# In Registry.init/1, after loading config topics:
def init(opts) do
  # ... create ETS table, load config topics ...

  # Register legacy aliases if enabled
  if Application.get_env(:synapse, :legacy_signals, true) do
    register_legacy_signals(state)
  end

  {:ok, state}
end

defp register_legacy_signals(state) do
  legacy_topics = [
    review_request: [
      type: "review.request",
      schema: [
        review_id: [type: :string, required: true],
        diff: [type: :string, default: ""],
        metadata: [type: :map, default: %{}],
        files_changed: [type: :integer, default: 0],
        labels: [type: {:list, :string}, default: []],
        intent: [type: :string, default: "feature"],
        risk_factor: [type: :float, default: 0.0],
        files: [type: {:list, :string}, default: []],
        language: [type: :string, default: "elixir"]
      ]
    ],
    review_result: [
      type: "review.result",
      schema: [
        review_id: [type: :string, required: true],
        agent: [type: :string, required: true],
        confidence: [type: :float, default: 0.0],
        findings: [type: {:list, :map}, default: []],
        should_escalate: [type: :boolean, default: false],
        metadata: [type: :map, default: %{}]
      ]
    ],
    review_summary: [
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
    ],
    specialist_ready: [
      type: "review.specialist_ready",
      schema: [
        specialist_id: [type: :string, required: true],
        capabilities: [type: {:list, :string}, default: []]
      ]
    ]
  ]

  Enum.each(legacy_topics, fn {topic, config} ->
    do_register_topic(state.table, topic, config)
  end)
end
```

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `test/synapse/signal/registry_test.exs` | CREATE |
| `lib/synapse/signal/registry.ex` | CREATE |
| `test/synapse/signal_test.exs` | CREATE/UPDATE |
| `lib/synapse/signal.ex` | MODIFY (delegate to registry) |
| `lib/synapse/signal/schema.ex` | MODIFY (add compile_schema/1) |
| `config/config.exs` | MODIFY (add signal topics) |
| `lib/synapse/application.ex` | MODIFY (add Registry to supervision) |

---

## Validation Checklist

After implementation, verify:

1. [ ] All new tests pass: `mix test test/synapse/signal/`
2. [ ] All existing tests pass: `mix test`
3. [ ] No compiler warnings: `mix compile --warnings-as-errors`
4. [ ] Dialyzer passes: `mix dialyzer`
5. [ ] Format check passes: `mix format --check-formatted`

Run full validation:
```bash
mix deps.get && mix compile --warnings-as-errors && mix format --check-formatted && mix dialyzer && mix test
```

---

## Final Steps: Update CHANGELOG and README

### Update CHANGELOG.md

Add entry at the top:

```markdown
## [0.1.1] - 2025-11-29

### Added
- Dynamic signal registry (`Synapse.Signal.Registry`) replacing hardcoded signal topics
- Runtime signal topic registration via `Synapse.Signal.register_topic/2`
- Configuration-based signal topic definition in `config/config.exs`
- Generic signal types: `:task_request`, `:task_result`, `:task_summary`, `:worker_ready`

### Changed
- `Synapse.Signal` now delegates to `Synapse.Signal.Registry`
- Signal topics are loaded from application config on startup

### Deprecated
- Direct use of `:review_request`, `:review_result`, `:review_summary` signals
  (still supported via legacy aliases, will be moved to optional domain in future release)
```

### Update README.md

Update version badge and add section about custom signals:

1. Change version references from `0.1.0` to `0.1.1`

2. Add new section after "Submit a Review Request":

```markdown
## Custom Signal Domains

Synapse supports custom signal domains beyond code review. Define your own signals in config:

\`\`\`elixir
# config/config.exs
config :synapse, Synapse.Signal.Registry,
  topics: [
    ticket_created: [
      type: "support.ticket.created",
      schema: [
        ticket_id: [type: :string, required: true],
        customer_id: [type: :string, required: true],
        subject: [type: :string, required: true],
        priority: [type: {:in, [:low, :medium, :high]}, default: :medium]
      ]
    ]
  ]
\`\`\`

Or register at runtime:

\`\`\`elixir
Synapse.Signal.register_topic(:my_event,
  type: "my.domain.event",
  schema: [id: [type: :string, required: true]]
)
\`\`\`
```

---

## Success Criteria

Phase 1 is complete when:

1. `Synapse.Signal.Registry` exists and manages all signal topics
2. `Synapse.Signal` delegates to Registry (no hardcoded `@topics`)
3. Topics can be defined via config or runtime registration
4. All existing tests pass (backward compatibility via legacy aliases)
5. New registry tests pass
6. `mix test` - ALL TESTS PASSING
7. `mix compile --warnings-as-errors` - NO WARNINGS
8. `mix dialyzer` - NO ERRORS
9. CHANGELOG.md updated with v0.1.1 changes
10. README.md updated with v0.1.1 and custom signals documentation
