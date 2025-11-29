# Phase 2: Parallel Consumer Updates

**Agent Task:** Coordinate three parallel sub-agents to update Signal consumers.

**Version:** v0.1.1

**Prerequisites:** Phase 1 must be complete (Signal Registry exists and works).

---

## Initial Assessment Task

Before spawning sub-agents, verify Phase 1 completion:

```bash
# Verify Phase 1 is complete
mix compile --warnings-as-errors
mix test test/synapse/signal/registry_test.exs
mix test test/synapse/signal_test.exs

# Verify Signal module delegates to Registry
grep -n "defdelegate" lib/synapse/signal.ex

# Verify Registry is in supervision tree
grep -n "Signal.Registry" lib/synapse/application.ex
```

If any of these fail, STOP and report that Phase 1 is incomplete.

---

## Sub-Agent Architecture

Spawn three sub-agents in parallel. Each works on a single file with no overlap:

```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│ Sub-Agent 2A        │  │ Sub-Agent 2B        │  │ Sub-Agent 2C        │
│                     │  │                     │  │                     │
│ signal_router.ex    │  │ agent_config.ex     │  │ run_config.ex       │
│                     │  │                     │  │                     │
│ NO OTHER FILES      │  │ NO OTHER FILES      │  │ NO OTHER FILES      │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**CRITICAL: Each sub-agent may ONLY modify its assigned file and create tests for it.**

---

# Sub-Agent 2A: Signal Router

## Required Reading

```
lib/synapse/signal_router.ex
lib/synapse/signal.ex (understand new delegation pattern)
lib/synapse/signal/registry.ex (understand Registry API)
test/synapse/signal_router_test.exs
test/support/signal_router_helpers.ex
docs/20251129/domain-agnostic-signals/PLAN.md
```

## Context

The SignalRouter currently works with `Signal.topics()` and `Signal.type()`. After Phase 1, these delegate to the Registry. The router should continue working without changes, but we want to verify and potentially add support for dynamic topic subscription.

## Task

### Step 1: Verify Existing Tests Pass

```bash
mix test test/synapse/signal_router_test.exs
```

If tests fail, the issue is likely in Phase 1. Report and stop.

### Step 2: Add Tests for Dynamic Topic Support

Create or update tests in `test/synapse/signal_router_test.exs`:

```elixir
describe "dynamic topic support" do
  test "router works with config-defined topics" do
    {:ok, router} = SignalRouter.start_link(name: :"test_router_#{:rand.uniform(100_000)}")

    # Subscribe to a generic topic (defined in config)
    {:ok, _sub_id} = SignalRouter.subscribe(router, :task_request)

    # Publish should work
    {:ok, signal} = SignalRouter.publish(router, :task_request, %{task_id: "test-123"})
    assert signal.type == "synapse.task.request"

    # Should receive the signal
    assert_receive {:signal, received}, 1000
    assert received.data.task_id == "test-123"

    GenServer.stop(router)
  end

  test "router works with runtime-registered topics" do
    # Register a custom topic
    topic = :"custom_topic_#{:rand.uniform(100_000)}"
    :ok = Synapse.Signal.register_topic(topic,
      type: "test.custom.#{topic}",
      schema: [id: [type: :string, required: true]]
    )

    {:ok, router} = SignalRouter.start_link(name: :"test_router_#{:rand.uniform(100_000)}")

    # Subscribe to runtime-registered topic
    {:ok, _sub_id} = SignalRouter.subscribe(router, topic)

    # Publish should work
    {:ok, signal} = SignalRouter.publish(router, topic, %{id: "runtime-123"})

    assert_receive {:signal, received}, 1000
    assert received.data.id == "runtime-123"

    GenServer.stop(router)
  end

  test "subscribing to unregistered topic raises InvalidTopicError" do
    {:ok, router} = SignalRouter.start_link(name: :"test_router_#{:rand.uniform(100_000)}")

    assert_raise SignalRouter.InvalidTopicError, fn ->
      SignalRouter.subscribe(router, :nonexistent_topic)
    end

    GenServer.stop(router)
  end
end
```

### Step 3: Verify/Update Router Implementation

Review `lib/synapse/signal_router.ex` and ensure:

1. `init/1` uses `Signal.topics()` which now reads from Registry
2. `ensure_topic!/2` validates against dynamic topic list
3. `subscribe_to_topics/1` subscribes to all registered topics

The router should already work because it uses `Signal.topics()` and `Signal.type()` which delegate to Registry. Verify no hardcoded topic references exist:

```bash
# Should return NO matches for hardcoded review topics
grep -n ":review_request\|:review_result\|:review_summary" lib/synapse/signal_router.ex
```

If hardcoded references exist, refactor to use `Signal.topics()`.

### Step 4: Run Tests

```bash
mix test test/synapse/signal_router_test.exs
```

## Files to Modify

| File | Action |
|------|--------|
| `lib/synapse/signal_router.ex` | VERIFY/MINOR UPDATES |
| `test/synapse/signal_router_test.exs` | ADD TESTS |

## Deliverables

- [ ] All existing signal_router tests pass
- [ ] New dynamic topic tests pass
- [ ] No hardcoded topic references in signal_router.ex
- [ ] Router works with config-defined and runtime-registered topics

---

# Sub-Agent 2B: Agent Config

## Required Reading

```
lib/synapse/orchestrator/agent_config.ex
lib/synapse/signal.ex (understand new delegation pattern)
lib/synapse/signal/registry.ex (understand Registry API)
test/synapse/orchestrator/agent_config_test.exs
priv/orchestrator_agents.exs (example config)
docs/20251129/domain-agnostic-signals/PLAN.md
```

## Context

`AgentConfig` validates signal topics against `Signal.topics()`. It needs to:
1. Continue working with the dynamic registry
2. Add support for `roles` in the signals configuration

## Task

### Step 1: Add Tests for Signal Roles

Create or update `test/synapse/orchestrator/agent_config_test.exs`:

```elixir
describe "signals with roles" do
  test "accepts signals with explicit roles" do
    config = %{
      id: :test_orchestrator,
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
      orchestration: %{
        classify_fn: fn _ -> %{path: :default} end,
        spawn_specialists: [],
        aggregation_fn: fn _, _ -> %{} end
      }
    }

    assert {:ok, %AgentConfig{} = validated} = AgentConfig.new(config)
    assert validated.signals.roles.request == :task_request
    assert validated.signals.roles.result == :task_result
    assert validated.signals.roles.summary == :task_summary
  end

  test "infers default roles from topic names when not specified" do
    config = %{
      id: :test_orchestrator,
      type: :orchestrator,
      signals: %{
        subscribes: [:task_request, :task_result],
        emits: [:task_summary]
      },
      orchestration: %{
        classify_fn: fn _ -> %{path: :default} end,
        spawn_specialists: [],
        aggregation_fn: fn _, _ -> %{} end
      }
    }

    assert {:ok, %AgentConfig{} = validated} = AgentConfig.new(config)
    # Should infer roles from topic names containing request/result
    assert validated.signals.roles.request == :task_request
    assert validated.signals.roles.result == :task_result
    assert validated.signals.roles.summary == :task_summary
  end

  test "roles default to nil for specialist agents" do
    config = %{
      id: :test_specialist,
      type: :specialist,
      actions: [SomeAction],
      signals: %{
        subscribes: [:task_request],
        emits: [:task_result]
      }
    }

    assert {:ok, %AgentConfig{} = validated} = AgentConfig.new(config)
    # Specialists don't need roles
    assert validated.signals.roles == nil or validated.signals.roles == %{}
  end

  test "validates that role topics are in subscribes or emits" do
    config = %{
      id: :test_orchestrator,
      type: :orchestrator,
      signals: %{
        subscribes: [:task_request],
        emits: [:task_summary],
        roles: %{
          request: :task_request,
          result: :nonexistent_topic,  # Not in subscribes!
          summary: :task_summary
        }
      },
      orchestration: %{
        classify_fn: fn _ -> %{} end,
        spawn_specialists: [],
        aggregation_fn: fn _, _ -> %{} end
      }
    }

    assert {:error, _} = AgentConfig.new(config)
  end
end

describe "signals with dynamic topics" do
  test "validates topics against registry" do
    # Register a custom topic
    topic = :"agent_config_test_topic_#{:rand.uniform(100_000)}"
    :ok = Synapse.Signal.register_topic(topic,
      type: "test.#{topic}",
      schema: [id: [type: :string, required: true]]
    )

    config = %{
      id: :test_specialist,
      type: :specialist,
      actions: [SomeAction],
      signals: %{
        subscribes: [topic],
        emits: []
      }
    }

    assert {:ok, %AgentConfig{}} = AgentConfig.new(config)
  end

  test "rejects unregistered topics" do
    config = %{
      id: :test_specialist,
      type: :specialist,
      actions: [SomeAction],
      signals: %{
        subscribes: [:completely_unknown_topic],
        emits: []
      }
    }

    assert {:error, _} = AgentConfig.new(config)
  end
end
```

### Step 2: Update AgentConfig Implementation

Modify `lib/synapse/orchestrator/agent_config.ex`:

#### Update signal_config type

```elixir
@typedoc "Signal configuration normalised by the schema"
@type signal_config :: %{
        subscribes: [signal_topic()],
        emits: [signal_topic()],
        roles: signal_roles() | nil
      }

@typedoc "Signal role mappings for orchestrators"
@type signal_roles :: %{
        request: signal_topic() | nil,
        result: signal_topic() | nil,
        summary: signal_topic() | nil
      }
```

#### Update validate_signals/1

```elixir
@doc false
def validate_signals(%{} = value) do
  with {:ok, subscribes} <- fetch_signal_list(value, :subscribes, required?: true),
       {:ok, emits} <- fetch_signal_list(value, :emits, required?: false),
       {:ok, roles} <- fetch_signal_roles(value, subscribes, emits) do
    {:ok, %{subscribes: subscribes, emits: emits, roles: roles}}
  end
end

defp fetch_signal_roles(map, subscribes, emits) do
  case Map.get(map, :roles) do
    nil ->
      # Infer roles from topic names for orchestrators
      {:ok, infer_roles(subscribes, emits)}

    %{} = roles ->
      # Validate explicit roles
      validate_explicit_roles(roles, subscribes, emits)

    other ->
      {:error, "roles must be a map, got #{inspect(other)}"}
  end
end

defp infer_roles(subscribes, emits) do
  %{
    request: find_topic_by_suffix(subscribes, "request"),
    result: find_topic_by_suffix(subscribes, "result"),
    summary: find_topic_by_suffix(emits, "summary") || List.first(emits)
  }
end

defp find_topic_by_suffix(topics, suffix) do
  Enum.find(topics, fn topic ->
    topic
    |> Atom.to_string()
    |> String.ends_with?(suffix)
  end)
end

defp validate_explicit_roles(roles, subscribes, emits) do
  all_topics = subscribes ++ emits

  errors =
    roles
    |> Enum.filter(fn {_role, topic} -> topic != nil and topic not in all_topics end)
    |> Enum.map(fn {role, topic} ->
      "role :#{role} references topic #{inspect(topic)} which is not in subscribes or emits"
    end)

  case errors do
    [] -> {:ok, roles}
    _ -> {:error, Enum.join(errors, "; ")}
  end
end
```

#### Update normalize_topic to use Registry

The existing code already uses `Signal.topics()` which now delegates to Registry:

```elixir
defp normalize_topic(topic) when is_atom(topic) do
  if topic in Signal.topics() do  # This now reads from Registry
    {:ok, topic}
  else
    {:error, "unknown signal topic #{inspect(topic)}"}
  end
end
```

No changes needed here.

### Step 3: Run Tests

```bash
mix test test/synapse/orchestrator/agent_config_test.exs
```

## Files to Modify

| File | Action |
|------|--------|
| `lib/synapse/orchestrator/agent_config.ex` | MODIFY (add roles) |
| `test/synapse/orchestrator/agent_config_test.exs` | ADD TESTS |

## Deliverables

- [ ] `roles` map support in signals config
- [ ] Default role inference from topic names
- [ ] Role validation (topics must be in subscribes/emits)
- [ ] Backward compatibility (roles optional)
- [ ] All agent_config tests pass

---

# Sub-Agent 2C: Orchestrator Run Config

## Required Reading

```
lib/synapse/orchestrator/actions/run_config.ex
lib/synapse/signal.ex
lib/synapse/orchestrator/agent_config.ex (understand roles after 2B)
test/synapse/orchestrator/actions/run_config_test.exs
docs/20251129/domain-agnostic-signals/PLAN.md
```

## Context

`run_config.ex` has hardcoded signal type matching:

```elixir
signal.type == Signal.type(:review_request) ->
  handle_orchestrator_request(...)

signal.type == Signal.type(:review_result) ->
  handle_orchestrator_result(...)
```

This needs to read from `config.signals.roles` instead.

Also, state keys use review terminology (`reviews`, `fast_path`, `deep_review`) which should become generic (`tasks`, `routed`, `dispatched`).

## Task

### Step 1: Add Tests for Config-Driven Dispatch

Create or update `test/synapse/orchestrator/actions/run_config_test.exs`:

```elixir
describe "config-driven signal dispatch" do
  test "dispatches based on roles.request topic" do
    config = %AgentConfig{
      id: :test_coordinator,
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
      actions: [],
      orchestration: %{
        classify_fn: fn _ -> %{path: :fast_path} end,
        spawn_specialists: [],
        aggregation_fn: fn _, state -> %{task_id: state.task_id, status: :complete} end
      }
    }

    # Create a task_request signal
    {:ok, signal} = Jido.Signal.new(%{
      type: "synapse.task.request",
      source: "/test",
      data: %{task_id: "test-123", payload: %{}}
    })

    params = %{
      _config: config,
      _signal: signal,
      _state: nil
    }

    assert {:ok, result} = RunConfig.run(params, %{})
    assert result.state.tasks["test-123"] || result.state.stats.total > 0
  end

  test "dispatches based on roles.result topic" do
    config = %AgentConfig{
      id: :test_coordinator,
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
      actions: [],
      orchestration: %{
        classify_fn: fn _ -> %{path: :deep_review} end,
        spawn_specialists: [:worker_a],
        aggregation_fn: fn results, state ->
          %{task_id: state.task_id, status: :complete, results: results}
        end
      }
    }

    # First, send a request to create task state
    {:ok, request_signal} = Jido.Signal.new(%{
      type: "synapse.task.request",
      source: "/test",
      data: %{task_id: "test-456", payload: %{}}
    })

    {:ok, %{state: state}} = RunConfig.run(%{
      _config: config,
      _signal: request_signal,
      _state: nil
    }, %{})

    # Now send a result signal
    {:ok, result_signal} = Jido.Signal.new(%{
      type: "synapse.task.result",
      source: "/test",
      data: %{task_id: "test-456", agent: "worker_a", output: %{}}
    })

    {:ok, result} = RunConfig.run(%{
      _config: config,
      _signal: result_signal,
      _state: state
    }, %{})

    # Task should be completed (pending workers resolved)
    assert result.state.stats.completed >= 0
  end

  test "uses legacy review topics when roles not specified" do
    # Backward compatibility test
    config = %AgentConfig{
      id: :legacy_coordinator,
      type: :orchestrator,
      signals: %{
        subscribes: [:review_request, :review_result],
        emits: [:review_summary],
        roles: nil  # No roles specified
      },
      actions: [],
      orchestration: %{
        classify_fn: fn _ -> %{path: :fast_path} end,
        spawn_specialists: [],
        aggregation_fn: fn _, state ->
          %{review_id: state.task_id, status: :complete}
        end
      }
    }

    {:ok, signal} = Jido.Signal.new(%{
      type: "review.request",
      source: "/test",
      data: %{review_id: "PR-123", diff: ""}
    })

    params = %{
      _config: config,
      _signal: signal,
      _state: nil
    }

    # Should still work with legacy signals
    assert {:ok, _result} = RunConfig.run(params, %{})
  end
end

describe "generic state keys" do
  test "uses tasks instead of reviews in state" do
    config = orchestrator_config()

    {:ok, signal} = Jido.Signal.new(%{
      type: "synapse.task.request",
      source: "/test",
      data: %{task_id: "state-test-123", payload: %{}}
    })

    {:ok, result} = RunConfig.run(%{
      _config: config,
      _signal: signal,
      _state: nil
    }, %{})

    # State should use :tasks not :reviews
    assert Map.has_key?(result.state, :tasks)
    refute Map.has_key?(result.state, :reviews)
  end

  test "stats use generic keys" do
    config = orchestrator_config()

    {:ok, signal} = Jido.Signal.new(%{
      type: "synapse.task.request",
      source: "/test",
      data: %{task_id: "stats-test", payload: %{}}
    })

    {:ok, result} = RunConfig.run(%{
      _config: config,
      _signal: signal,
      _state: nil
    }, %{})

    stats = result.state.stats
    assert Map.has_key?(stats, :total)
    assert Map.has_key?(stats, :routed) or Map.has_key?(stats, :completed)
  end

  defp orchestrator_config do
    %AgentConfig{
      id: :test_coord,
      type: :orchestrator,
      signals: %{
        subscribes: [:task_request, :task_result],
        emits: [:task_summary],
        roles: %{request: :task_request, result: :task_result, summary: :task_summary}
      },
      actions: [],
      orchestration: %{
        classify_fn: fn _ -> %{path: :routed} end,
        spawn_specialists: [],
        aggregation_fn: fn _, s -> %{task_id: s.task_id, status: :complete} end
      }
    }
  end
end
```

### Step 2: Update RunConfig Implementation

Modify `lib/synapse/orchestrator/actions/run_config.ex`:

#### Update defaults

```elixir
# Replace review terminology with generic terms
@orchestrator_defaults %{
  tasks: %{},  # was: reviews
  stats: %{total: 0, routed: 0, dispatched: 0, completed: 0, failed: 0}
}
```

#### Update run_orchestrator/2

```elixir
defp run_orchestrator(config, params) do
  router = Map.get(params, :_router)
  state = Map.get(params, :_state) || initial_state(config)
  signal = Map.get(params, :_signal)
  emits = Map.get(params, :_emits, config.signals.emits || [])
  orchestration = Map.get(config, :orchestration) || %{}

  # Get topic roles from config, with fallback to legacy defaults
  roles = get_signal_roles(config)
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

defp get_signal_roles(config) do
  case get_in(config, [:signals, :roles]) do
    %{request: _, result: _} = roles ->
      Map.merge(default_roles(), roles)

    _ ->
      # Infer from subscribes for backward compatibility
      infer_roles_from_signals(config.signals)
  end
end

defp default_roles do
  %{
    request: :task_request,
    result: :task_result,
    summary: :task_summary
  }
end

defp infer_roles_from_signals(%{subscribes: subscribes, emits: emits}) do
  %{
    request: find_role_topic(subscribes, ~w(request)),
    result: find_role_topic(subscribes, ~w(result)),
    summary: find_role_topic(emits, ~w(summary)) || List.first(emits)
  }
end

defp find_role_topic(topics, suffixes) do
  Enum.find(topics, fn topic ->
    topic_str = Atom.to_string(topic)
    Enum.any?(suffixes, &String.ends_with?(topic_str, &1))
  end)
end

defp initial_state(config) do
  case Map.get(config, :initial_state) do
    nil -> @orchestrator_defaults
    %{} = custom -> Map.merge(@orchestrator_defaults, custom)
    _ -> @orchestrator_defaults
  end
end
```

#### Rename internal state keys

Throughout the file, rename:
- `reviews` → `tasks`
- `review_id` → `task_id`
- `review_state` → `task_state`
- `review_data` → `task_data`
- `fast_path` → `routed` (in stats)
- `deep_review` → `dispatched` (in stats)

Use find-and-replace carefully, preserving signal payload field names (those come from user data and shouldn't change).

#### Update build_review_state → build_task_state

```elixir
defp build_task_state(signal, classification, specialists) do
  task_id = extract_task_id(signal.data)

  %{
    task_id: task_id,
    classification: classification,
    classification_path: classification_path(classification),
    pending: Enum.map(specialists, &normalize_specialist_id/1),
    results: [],
    started_at: System.monotonic_time(:millisecond),
    signal: signal,
    metadata: %{
      decision_path: classification_path(classification),
      specialists_resolved: [],
      duration_ms: 0,
      negotiations: []
    }
  }
end

# Extract task_id from signal data, supporting both generic and legacy field names
defp extract_task_id(data) do
  Map.get(data, :task_id) ||
    Map.get(data, "task_id") ||
    Map.get(data, :review_id) ||  # Legacy support
    Map.get(data, "review_id")
end
```

#### Update state management functions

```elixir
defp ensure_orchestrator_state(state) do
  state
  |> Map.put_new(:tasks, %{})
  |> Map.put_new(:stats, %{total: 0, routed: 0, dispatched: 0, completed: 0, failed: 0})
end

defp increment_stat(state, :fast_path), do: increment_stat(state, :routed)
defp increment_stat(state, :deep_review), do: increment_stat(state, :dispatched)
defp increment_stat(state, key) do
  update_in(state, [:stats, key], fn
    nil -> 1
    value -> value + 1
  end)
end
```

### Step 3: Run Tests

```bash
mix test test/synapse/orchestrator/actions/run_config_test.exs
```

## Files to Modify

| File | Action |
|------|--------|
| `lib/synapse/orchestrator/actions/run_config.ex` | MODIFY (roles + generic state) |
| `test/synapse/orchestrator/actions/run_config_test.exs` | ADD TESTS |

## Deliverables

- [ ] Config-driven signal type dispatch using `config.signals.roles`
- [ ] Fallback to inferred roles for backward compatibility
- [ ] Generic state keys (`tasks`, `routed`, `dispatched`)
- [ ] `initial_state` support from agent config
- [ ] All run_config tests pass

---

# Coordinator Agent: Final Steps

After all three sub-agents complete, run full validation:

```bash
# Full test suite
mix test

# Compiler warnings
mix compile --warnings-as-errors

# Dialyzer
mix dialyzer

# Format check
mix format --check-formatted
```

## Update CHANGELOG.md

Add/update the Phase 2 changes (append to Phase 1 entry if same version):

```markdown
## [0.1.1] - 2025-11-29

### Added
- Dynamic signal registry (`Synapse.Signal.Registry`) replacing hardcoded signal topics
- Runtime signal topic registration via `Synapse.Signal.register_topic/2`
- Configuration-based signal topic definition in `config/config.exs`
- Generic signal types: `:task_request`, `:task_result`, `:task_summary`, `:worker_ready`
- Signal `roles` configuration in agent config for orchestrators
- `initial_state` support in orchestrator agent config

### Changed
- `Synapse.Signal` now delegates to `Synapse.Signal.Registry`
- Signal topics are loaded from application config on startup
- `SignalRouter` works with dynamically registered topics
- `AgentConfig` validates topics against dynamic registry
- `RunConfig` dispatches based on configurable `signals.roles`
- Orchestrator state uses generic keys (`tasks` instead of `reviews`)

### Deprecated
- Direct use of `:review_request`, `:review_result`, `:review_summary` signals
  (still supported via legacy aliases, will be moved to optional domain in future release)
- State keys `reviews`, `fast_path`, `deep_review` (use `tasks`, `routed`, `dispatched`)
```

## Update README.md

Ensure version is `0.1.1` and custom signals documentation is present (from Phase 1).

Add section about agent config roles if not present:

```markdown
## Agent Configuration

Orchestrator agents can specify signal roles for custom domains:

\`\`\`elixir
%{
  id: :my_coordinator,
  type: :orchestrator,
  signals: %{
    subscribes: [:ticket_created, :ticket_analyzed],
    emits: [:ticket_resolved],
    roles: %{
      request: :ticket_created,
      result: :ticket_analyzed,
      summary: :ticket_resolved
    }
  },
  orchestration: %{
    classify_fn: &MyApp.classify/1,
    spawn_specialists: [:analyzer, :responder],
    aggregation_fn: &MyApp.aggregate/2
  }
}
\`\`\`
```

---

## Success Criteria

Phase 2 is complete when:

1. Sub-agent 2A: SignalRouter works with dynamic topics
2. Sub-agent 2B: AgentConfig supports signal roles
3. Sub-agent 2C: RunConfig uses config-driven dispatch and generic state
4. `mix test` - ALL TESTS PASSING
5. `mix compile --warnings-as-errors` - NO WARNINGS
6. `mix dialyzer` - NO ERRORS
7. `mix format --check-formatted` - PASSES
8. CHANGELOG.md updated with Phase 2 changes
9. README.md reflects v0.1.1 with new features documented
