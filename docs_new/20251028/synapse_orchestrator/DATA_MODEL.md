# Synapse Orchestrator Data Model

**Complete reference for all data structures in the orchestrator system**

## Overview

The Synapse Orchestrator uses a layered data model that transforms declarative configurations into runtime state and finally into running agent processes. Understanding these data structures is crucial for working with the orchestrator.

## Data Flow Pipeline

```
┌─────────────────────────┐
│  1. Configuration Map   │  ← Written by humans
│  (Elixir map)          │
└──────────┬──────────────┘
           │ Load & Validate
           ▼
┌─────────────────────────┐
│  2. Validated Config    │  ← Type-safe struct (Synapse.Orchestrator.AgentConfig)
│  (AgentConfig struct)   │
└──────────┬──────────────┘
           │ Spawn via Factory
           ▼
┌─────────────────────────┐
│  3. Runtime State       │  ← Tracked by Runtime
│  (RunningAgent struct)  │
└──────────┬──────────────┘
           │ Creates
           ▼
┌─────────────────────────┐
│  4. Agent Instance      │  ← Jido.Agent.Server
│  (Running process)      │
└─────────────────────────┘
```

## Layer 1: Configuration Data

### AgentConfig (Input Configuration)

**Purpose**: Human-written agent definition that gets normalized by the orchestrator

**Type Specification**:

```elixir
@type agent_id :: atom()
@type agent_type :: :specialist | :orchestrator | :custom
@type signal_pattern :: String.t()
@type agent_config :: Synapse.Orchestrator.AgentConfig.t()

@type signal_config :: %{
  subscribes: [signal_pattern()],
  emits: [signal_pattern()]
}

@type result_builder_fn :: (
  action_results :: [action_result()],
  context :: any()
  -> result_map :: map()
) |
(
  action_results :: [action_result()],
  context :: any(),
  config :: agent_config()
  -> result_map :: map()
)

@type custom_handler_fn :: (
  signal :: Jido.Signal.t(),
  state :: map()
  -> {:ok, map()} | {:stop, term(), map()} | {:noreply, map()}
)

@type action_result :: {:ok, map()} | {:error, term()}
```

- **Module**: `Synapse.Orchestrator.AgentConfig` (`lib/synapse/orchestrator/agent_config.ex`)
- **Schema**: `schema/0` exposes the NimbleOptions definition for configuration files
- **Constructor**: `new/1` validates user input and returns the struct or an error

**Archetype requirements**:

- **Specialist** agents **must** provide a non-empty `actions` list. Optional helpers like
  `result_builder` and `state_schema` tailor execution, but the action list is mandatory.
- **Orchestrator** agents **must** provide an `orchestration` map. They may also list `actions` if
  they run local work (for example, pre-processing or synthesis steps).
- **Custom** agents **must** provide `custom_handler`. They may combine that handler with `actions`
  when they want the standard action pipeline before custom logic runs.

**Example**:

```elixir
%{
  id: :security_specialist,
  type: :specialist,
  actions: [CheckSQLInjection, CheckXSS, CheckAuthIssues],
  signals: %{
    subscribes: ["review.request"],
    emits: ["review.result"]
  },
  result_builder: fn results, review_id ->
    %{
      review_id: review_id,
      agent: "security_specialist",
      findings: extract_findings(results)
    }
  end,
  state_schema: [
    review_history: [type: {:list, :map}, default: []]
  ],
  bus: :synapse_bus,
  registry: :synapse_registry
}
```

### OrchestrationConfig

**Purpose**: Orchestrator-specific behavior configuration

**Type Specification**:

```elixir
@type orchestration_config :: %{
  required(:classify_fn) => classify_fn(),
  required(:spawn_specialists) => specialist_list(),
  required(:aggregation_fn) => aggregation_fn(),
  optional(:fast_path_fn) => fast_path_fn()
}

@type classify_fn :: (review_data :: map() -> classification())
@type classification :: %{
  path: :fast_path | :deep_review,
  rationale: String.t()
}

@type specialist_list ::
  [agent_id()] |
  (review_data :: map() -> [agent_id()])

@type aggregation_fn :: (
  specialist_results :: [map()],
  review_state :: map()
  -> summary :: map()
)

@type fast_path_fn :: (
  signal :: Jido.Signal.t(),
  bus :: atom()
  -> :ok | {:error, term()}
)
```

**Example**:

```elixir
%{
  classify_fn: fn review_data ->
    if review_data.files_changed > 50 do
      %{path: :deep_review, rationale: "Large change"}
    else
      %{path: :fast_path, rationale: "Small change"}
    end
  end,

  spawn_specialists: [:security_specialist, :performance_specialist],

  aggregation_fn: fn specialist_results, review_state ->
    %{
      review_id: review_state.review_id,
      status: :complete,
      findings: Enum.flat_map(specialist_results, & &1.findings)
    }
  end,

  fast_path_fn: fn signal, bus ->
    emit_fast_summary(signal, bus)
    :ok
  end
}
```

### StateSchema

**Purpose**: Agent state structure definition

**Type Specification**:

```elixir
@type state_schema :: keyword()
@type field_schema :: [
  {:type, nimble_type()},
  {:default, any()},
  {:required, boolean()},
  {:doc, String.t()}
]

@type nimble_type ::
  :string | :integer | :float | :boolean | :atom | :map |
  {:list, nimble_type()} |
  {:in, [any()]} |
  :any
```

**Example**:

```elixir
[
  # Simple fields
  review_count: [type: :integer, default: 0],
  status: [type: :atom, default: :idle],

  # Complex fields
  review_history: [
    type: {:list, :map},
    default: [],
    doc: "Last 100 reviews processed"
  ],

  learned_patterns: [
    type: {:list, :map},
    default: [],
    doc: "Patterns learned from corrections"
  ],

  active_reviews: [
    type: :map,
    default: %{},
    doc: "Currently active reviews by ID"
  ],

  # Constrained fields
  priority: [
    type: {:in, [:low, :medium, :high]},
    default: :medium
  ]
]
```

## Layer 2: Runtime State

### Runtime State

**Purpose**: Orchestrator runtime manager state

**Struct Definition** (conceptual):

```elixir
defmodule Synapse.Orchestrator.Runtime.State do
  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.Orchestrator.Runtime.RunningAgent

  @type t :: %__MODULE__{
    config_source: String.t() | module(),
    agent_configs: [AgentConfig.t()],
    running_agents: running_agents(),
    monitors: monitors(),
    bus: atom() | nil,
    registry: atom() | nil,
    reconcile_interval: pos_integer(),
    last_reconcile: DateTime.t() | nil,
    reconcile_count: non_neg_integer(),
    metadata: map(),
    skill_registry: pid() | nil,
    skills_summary: String.t()
  }

  @type running_agents :: %{optional(agent_id()) => RunningAgent.t()}
  @type monitors :: %{optional(reference()) => agent_id()}

  defstruct [
    :config_source,
    :agent_configs,
    :running_agents,
    :monitors,
    :bus,
    :registry,
    :reconcile_interval,
    :last_reconcile,
    :reconcile_count,
    metadata: %{},
    skill_registry: nil,
    skills_summary: ""
  ]
end
```

**Example Instance**:

```elixir
%Runtime.State{
  config_source: "config/agents.exs",

  agent_configs: [
    %Synapse.Orchestrator.AgentConfig{id: :security_specialist, type: :specialist, ...},
    %Synapse.Orchestrator.AgentConfig{id: :performance_specialist, type: :specialist, ...},
    %Synapse.Orchestrator.AgentConfig{id: :coordinator, type: :orchestrator, ...}
  ],

  running_agents: %{
    security_specialist: %RunningAgent{
      pid: #PID<0.456.0>,
      monitor_ref: #Reference<0.123.0>,
      spawn_count: 1
    },
    performance_specialist: %RunningAgent{
      pid: #PID<0.457.0>,
      monitor_ref: #Reference<0.124.0>,
      spawn_count: 1
    },
    coordinator: %RunningAgent{
      pid: #PID<0.458.0>,
      monitor_ref: #Reference<0.125.0>,
      spawn_count: 2,
      last_error: {:crash, :timeout}
    }
  },

  monitors: %{
    #Reference<0.123.0> => :security_specialist,
    #Reference<0.124.0> => :performance_specialist,
    #Reference<0.125.0> => :coordinator
  },

  bus: :synapse_bus,
  registry: :synapse_registry,
  reconcile_interval: 5000,
  last_reconcile: ~U[2025-10-29 12:00:00Z],
  reconcile_count: 42,

  metadata: %{
    started_at: ~U[2025-10-29 10:00:00Z],
    total_spawns: 45,
    total_respawns: 3
  },
  skill_registry: #PID<0.601.0>,
  skills_summary: "- demo-skill: Demo instructions\n  (Load: bash cat /tmp/.../SKILL.md)"
}
```

### RunningAgent

**Purpose**: Track individual running agent with metadata the runtime needs for reconciliation

**Struct Definition** (`lib/synapse/orchestrator/runtime/running_agent.ex`):

```elixir
defmodule Synapse.Orchestrator.Runtime.RunningAgent do
  @enforce_keys [:agent_id, :pid, :config, :monitor_ref, :spawned_at, :spawn_count]
  defstruct [
    :agent_id,
    :pid,
    :config,
    :monitor_ref,
    :spawned_at,
    :spawn_count,
    last_error: nil,
    metadata: %{}
  ]
end

@type running_agent :: %RunningAgent{}
```

**Example**:

```elixir
%RunningAgent{
  agent_id: :security_specialist,
  pid: #PID<0.456.0>,
  config: %{id: :security_specialist, type: :specialist, ...},
  monitor_ref: #Reference<0.123.0>,
  spawned_at: ~U[2025-10-29 11:00:00Z],
  spawn_count: 1,
  last_error: nil,
  metadata: %{
    signals_processed: 156,
    actions_executed: 468,
    avg_latency_ms: 45
  }
}
```

Use `Synapse.Orchestrator.Runtime.RunningAgent.schema/0` for validation documentation and
`new/1` to enforce the rules before persisting runtime state. `Runtime.State.running_agents`
stores these structs per active agent, giving the reconciler the metadata it needs to restart or
retire processes intelligently. Each running process hosts the shared
`Synapse.Orchestrator.GenericAgent` module and delegates work to the
`Synapse.Orchestrator.Actions.RunConfig` action which executes the configured action list, invokes
custom result builders, and publishes outbound signals.

The skill registry (`Synapse.Orchestrator.Skill.Registry`) is also initialised by the runtime and
cached in `Runtime.State.skill_registry`. Metadata summaries are exposed via
`Synapse.Orchestrator.Runtime.skill_metadata/1`, making progressive disclosure easy to layer into
system prompts.

## Layer 3: Agent Instance State

### Specialist Agent State

**Purpose**: Runtime state of a specialist agent

**Type Specification**:

```elixir
@type specialist_state :: %{
  # From config.state_schema
  review_history: [review_entry()],
  learned_patterns: [pattern_entry()],
  scar_tissue: [scar_entry()],

  # Runtime tracking
  last_review_id: String.t() | nil,
  last_result: map() | nil,
  total_reviews: non_neg_integer(),
  total_findings: non_neg_integer()
}

@type review_entry :: %{
  review_id: String.t(),
  timestamp: DateTime.t(),
  issues_found: non_neg_integer(),
  severity: :none | :low | :medium | :high
}

@type pattern_entry :: %{
  pattern: String.t(),
  count: non_neg_integer(),
  examples: [any()],
  last_seen: DateTime.t()
}

@type scar_entry :: %{
  pattern: String.t(),
  mitigation: String.t(),
  timestamp: DateTime.t(),
  occurrences: non_neg_integer()
}
```

**Example**:

```elixir
%{
  # Configured fields
  review_history: [
    %{
      review_id: "review_001",
      timestamp: ~U[2025-10-29 11:30:00Z],
      issues_found: 2,
      severity: :high
    },
    %{
      review_id: "review_002",
      timestamp: ~U[2025-10-29 11:35:00Z],
      issues_found: 0,
      severity: :none
    }
  ],

  learned_patterns: [
    %{
      pattern: "sql_injection_string_concat",
      count: 15,
      examples: ["SELECT * FROM users WHERE id = '" <> "#{user_input}'"],
      last_seen: ~U[2025-10-29 11:30:00Z]
    }
  ],

  scar_tissue: [
    %{
      pattern: "false_positive_prepared_statement",
      mitigation: "Check for parameterized query pattern",
      timestamp: ~U[2025-10-28 10:00:00Z],
      occurrences: 3
    }
  ],

  # Runtime fields
  last_review_id: "review_002",
  last_result: %{review_id: "review_002", findings: []},
  total_reviews: 156,
  total_findings: 234
}
```

### Orchestrator Agent State

**Purpose**: Runtime state of an orchestrator agent

**Type Specification**:

```elixir
@type orchestrator_state :: %{
  # From config.state_schema
  review_count: non_neg_integer(),
  active_reviews: active_reviews(),
  fast_path_count: non_neg_integer(),
  deep_review_count: non_neg_integer(),

  # Runtime tracking
  total_specialists_spawned: non_neg_integer(),
  avg_review_duration_ms: float(),
  last_classification: classification() | nil
}

@type active_reviews :: %{optional(review_id()) => review_state()}

@type review_state :: %{
  status: :awaiting | :ready | :complete,
  pending_specialists: [agent_id()],
  results: [specialist_result()],
  start_time: integer(),
  classification_path: :fast_path | :deep_review,
  original_signal: Jido.Signal.t()
}

@type specialist_result :: %{
  review_id: String.t(),
  agent: String.t(),
  confidence: float(),
  findings: [finding()],
  should_escalate: boolean(),
  metadata: map()
}

@type finding :: %{
  type: atom(),
  severity: :none | :low | :medium | :high,
  file: String.t(),
  summary: String.t(),
  recommendation: String.t() | nil
}
```

**Example**:

```elixir
%{
  # Configured fields
  review_count: 156,

  active_reviews: %{
    "review_current_001" => %{
      status: :awaiting,
      pending_specialists: ["performance_specialist"],
      results: [
        %{
          review_id: "review_current_001",
          agent: "security_specialist",
          confidence: 0.92,
          findings: [
            %{
              type: :sql_injection,
              severity: :high,
              file: "lib/repo.ex",
              summary: "Potential SQL injection detected",
              recommendation: "Use parameterized queries"
            }
          ],
          should_escalate: true,
          metadata: %{runtime_ms: 45}
        }
      ],
      start_time: 1730203200000,
      classification_path: :deep_review,
      original_signal: %Jido.Signal{...}
    }
  },

  fast_path_count: 89,
  deep_review_count: 67,

  # Runtime tracking
  total_specialists_spawned: 134,
  avg_review_duration_ms: 78.5,
  last_classification: %{path: :deep_review, rationale: "Security label present"}
}
```

## Layer 4: Factory Intermediate Data

### AgentServerOptions

**Purpose**: Options passed to Jido.Agent.Server.start_link/1

**Type Specification**:

```elixir
@type agent_server_options :: [
  {:id, String.t()},
  {:bus, atom()},
  {:registry, atom()},
  {:actions, [action_module()]},
  {:routes, [route_spec()]},
  {:schema, keyword()},
  {:mode, :auto | :manual | :step}
]

@type route_spec :: {
  pattern :: String.t(),
  handler :: route_handler()
}

@type route_handler :: (Jido.Signal.t() -> {:ok, map()} | {:error, term()})
```

**Example**:

```elixir
[
  id: "security_specialist",
  bus: :synapse_bus,
  registry: :synapse_registry,

  actions: [
    Synapse.Actions.Security.CheckSQLInjection,
    Synapse.Actions.Security.CheckXSS,
    Synapse.Actions.Security.CheckAuthIssues
  ],

  routes: [
    {
      "review.request",
      fn signal ->
        # Execute actions
        results = Enum.map(actions, &Jido.Exec.run(&1, signal.data, %{}))

        # Build result
        result = result_builder.(results, signal.data.review_id)

        # Emit signal
        emit_result_signal(result, bus)

        # Return state update
        {:ok, %{last_review: signal.data.review_id}}
      end
    }
  ],

  schema: [
    review_history: [type: {:list, :map}, default: []]
  ],

  mode: :auto
]
```

### RouteHandler Data

**Purpose**: Captures signal processing logic for a route

**Type Specification**:

```elixir
@type route_handler_data :: %{
  pattern: String.t(),
  actions: [action_module()],
  result_builder: result_builder_fn(),
  emit_config: emit_config(),
  state_updater: state_updater_fn()
}

@type emit_config :: %{
  signal_type: String.t(),
  source_template: String.t(),
  subject_template: String.t()
}

@type state_updater_fn :: (
  current_state :: map(),
  signal :: Jido.Signal.t(),
  result :: map()
  -> updated_state :: map()
)
```

## Layer 5: Signal Data Structures

### Signal Payloads

#### Review Request Signal

**Type**: `review.request`
**Purpose**: Initiate code review

```elixir
%{
  review_id: String.t(),
  diff: String.t(),
  files_changed: non_neg_integer(),
  labels: [String.t()],
  intent: String.t(),
  risk_factor: float(),
  language: String.t(),
  metadata: %{
    author: String.t(),
    branch: String.t(),
    repo: String.t(),
    timestamp: DateTime.t(),
    files: [String.t()]
  }
}
```

#### Review Result Signal

**Type**: `review.result`
**Purpose**: Specialist findings

```elixir
%{
  review_id: String.t(),
  agent: String.t(),
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

#### Review Summary Signal

**Type**: `review.summary`
**Purpose**: Final review summary

```elixir
%{
  review_id: String.t(),
  status: :complete | :failed,
  severity: :none | :low | :medium | :high,
  findings: [finding()],
  recommendations: [String.t()],
  escalations: [String.t()],
  metadata: %{
    decision_path: :fast_path | :deep_review,
    specialists_resolved: [String.t()],
    duration_ms: non_neg_integer()
  }
}
```

## Data Transformations

### Configuration → Runtime State

**Transformation**: `Config.load/1 → Runtime.init/1`

```elixir
# Input: Raw configuration map
config_map = %{
  id: :security,
  type: :specialist,
  actions: [CheckSQL],
  signals: %{subscribes: ["review.request"], emits: ["review.result"]}
}

# Step 1: Validation
{:ok, validated_config} = Config.validate(config_map)

# Step 2: Runtime storage
runtime_state = %Runtime.State{
  agent_configs: [validated_config],
  running_agents: %{},
  ...
}

# Output: Runtime state ready for reconciliation
```

### Configuration → Agent Options

**Transformation**: `AgentFactory.spawn/3`

```elixir
# Input: Validated configuration
config = %{
  id: :security_specialist,
  type: :specialist,
  actions: [CheckSQL, CheckXSS],
  signals: %{subscribes: ["review.request"], emits: ["review.result"]},
  state_schema: [review_history: [type: {:list, :map}, default: []]]
}

# Transformation
agent_opts = [
  id: "security_specialist",
  bus: :synapse_bus,
  actions: [CheckSQL, CheckXSS],

  routes: [
    {
      "review.request",
      fn signal ->
        results = Enum.map([CheckSQL, CheckXSS], &execute_action(&1, signal))
        result_data = build_result(results, signal.data.review_id)
        emit_signal("review.result", result_data, :synapse_bus)
        {:ok, %{last_review: signal.data.review_id}}
      end
    }
  ],

  schema: [
    review_history: [type: {:list, :map}, default: []]
  ]
]

# Output: Jido.Agent.Server options
{:ok, pid} = Jido.Agent.Server.start_link(agent_opts)
```

### Action Results → Signal Data

**Transformation**: `result_builder.(results, context)`

```elixir
# Input: Action execution results
action_results = [
  {:ok, %{findings: [%{type: :sql_injection, severity: :high}], confidence: 0.9}},
  {:ok, %{findings: [], confidence: 0.85}},
  {:ok, %{findings: [%{type: :xss, severity: :medium}], confidence: 0.75}}
]

# Transformation (via result_builder)
result_data = %{
  review_id: "review_123",
  agent: "security_specialist",
  confidence: 0.833,  # Average
  findings: [
    %{type: :sql_injection, severity: :high, ...},
    %{type: :xss, severity: :medium, ...}
  ],
  should_escalate: true,  # Has high severity
  metadata: %{
    runtime_ms: 45,
    path: :deep_review,
    actions_run: [CheckSQL, CheckXSS, CheckAuth]
  }
}

# Output: Signal data ready for emission
{:ok, signal} = Jido.Signal.new(%{
  type: "review.result",
  source: "/synapse/agents/security_specialist",
  data: result_data
})
```

### Specialist Results → Summary

**Transformation**: `aggregation_fn.(results, review_state)`

```elixir
# Input: Multiple specialist results
specialist_results = [
  %{
    review_id: "review_123",
    agent: "security_specialist",
    findings: [%{type: :sql_injection, severity: :high, ...}],
    confidence: 0.9
  },
  %{
    review_id: "review_123",
    agent: "performance_specialist",
    findings: [%{type: :high_complexity, severity: :low, ...}],
    confidence: 0.7
  }
]

# Transformation
summary = %{
  review_id: "review_123",
  status: :complete,
  severity: :high,  # Max severity from all findings
  findings: [
    %{type: :sql_injection, severity: :high, ...},
    %{type: :high_complexity, severity: :low, ...}
  ],
  recommendations: [
    "Use parameterized queries",
    "Refactor complex functions"
  ],
  escalations: [],
  metadata: %{
    decision_path: :deep_review,
    specialists_resolved: ["security_specialist", "performance_specialist"],
    duration_ms: 95
  }
}

# Output: Summary signal data
{:ok, summary_signal} = Jido.Signal.new(%{
  type: "review.summary",
  source: "/synapse/agents/coordinator",
  data: summary
})
```

## State Transitions

### Runtime State Transitions

```
┌─────────────┐
│  Startup    │  config_source loaded, agent_configs validated
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Reconciling │  spawning/verifying/removing agents
└──────┬──────┘
       │ (every reconcile_interval)
       ▼
┌─────────────┐
│   Stable    │  all agents running, monitoring
└──────┬──────┘
       │ (agent crash or config change)
       ▼
┌─────────────┐
│ Reconciling │  fixing drift
└─────────────┘
```

**State Invariants**:
- `length(agent_configs) >= map_size(running_agents)` (some may not have spawned yet)
- `map_size(monitors) == map_size(running_agents)` (one monitor per agent)
- All pids in `running_agents` are monitored via `monitors`

### Agent Instance State Transitions

#### Specialist Agent

```
┌─────────┐
│  Idle   │  waiting for signals
└────┬────┘
     │ (review.request received)
     ▼
┌─────────┐
│Processing│ executing actions
└────┬────┘
     │ (actions complete)
     ▼
┌─────────┐
│ Emitting│  emitting review.result
└────┬────┘
     │
     ▼
┌─────────┐
│  Idle   │  state updated, ready for next
└─────────┘
```

#### Orchestrator Agent

```
┌─────────┐
│  Idle   │  waiting for signals
└────┬────┘
     │ (review.request received)
     ▼
┌──────────────┐
│ Classifying  │  running classify_fn
└────┬─────────┘
     │
     ├─ (fast_path) ──────────┐
     │                        ▼
     │                  ┌─────────────┐
     │                  │  Emitting   │
     │                  │  Summary    │
     │                  └──────┬──────┘
     │                         │
     │ (deep_review)           │
     ▼                         │
┌──────────────┐               │
│   Spawning   │  spawning specialists
│ Specialists  │               │
└────┬─────────┘               │
     │                         │
     ▼                         │
┌──────────────┐               │
│  Awaiting    │  tracking pending specialists
│   Results    │               │
└────┬─────────┘               │
     │ (all results received) │
     ▼                         │
┌──────────────┐               │
│ Aggregating  │  running aggregation_fn
└────┬─────────┘               │
     │                         │
     ▼                         │
┌──────────────┐               │
│  Emitting    │ ──────────────┘
│  Summary     │
└────┬─────────┘
     │
     ▼
┌─────────┐
│  Idle   │
└─────────┘
```

## Data Validation Rules

### Configuration Validation

**Performed by**: `Synapse.Orchestrator.Config.validate/1`

**Rules**:

```elixir
# 1. Required fields present
assert config.id != nil
assert config.type in [:specialist, :orchestrator, :custom]
assert config.signals != nil

# 2. Signal configuration valid
assert is_list(config.signals.subscribes)
assert is_list(config.signals.emits)
assert length(config.signals.subscribes) > 0
assert length(config.signals.emits) > 0

# 3. Action modules exist
if config.actions do
  assert is_list(config.actions)
  assert config.actions != []
  assert Enum.all?(config.actions, &is_atom/1)

  for action <- config.actions do
    assert Code.ensure_loaded?(action)
    assert function_exported?(action, :run, 2)
  end
end

# 4. Type-specific validation
case config.type do
  :specialist ->
    assert is_list(config.actions) && config.actions != []

    if config.result_builder do
      assert is_function(config.result_builder, 2)
    end

  :orchestrator ->
    # Required orchestration config
    assert config.orchestration != nil
    assert is_function(config.orchestration.classify_fn, 1)
    assert is_list(config.orchestration.spawn_specialists)
    assert is_function(config.orchestration.aggregation_fn, 2)

  :custom ->
    # Must provide custom handler
    assert is_function(config.custom_handler, 2)

    if config.actions do
      # Optional actions still need to be non-empty if provided
      assert config.actions != []
    end
end

# 5. State schema valid (if provided)
if config.state_schema do
  assert {:ok, _} = NimbleOptions.validate(%{}, config.state_schema)
end

# 6. No ID conflicts
assert agent_id_unique?(config.id, existing_configs)
```

### Runtime Validation

**Performed by**: `Runtime.reconcile_agents/1`

**Rules**:

```elixir
# 1. Agent existence
for config <- agent_configs do
  case Map.get(running_agents, config.id) do
    nil -> spawn_agent(config)  # Missing
    %RunningAgent{pid: pid, config: ^config} when Process.alive?(pid) -> :ok
    running -> restart_agent(running, config)  # Drift detected or crashed
  end
end

# 2. Dependency satisfaction
for config <- agent_configs do
  if config.depends_on do
    for dep_id <- config.depends_on do
      assert Map.has_key?(running_agents, dep_id),
        "Dependency #{dep_id} not running for #{config.id}"
    end
  end
end

# 3. Spawn condition
for config <- agent_configs do
  if config.spawn_condition do
    should_spawn = config.spawn_condition.()

    case {should_spawn, Map.get(running_agents, config.id)} do
      {true, nil} -> spawn_agent(config)
      {false, %RunningAgent{} = running} -> stop_agent(running.pid)
      _ -> :ok
    end
  end
end
```

Skill metadata is cached on each reconciliation so calls to
`Synapse.Orchestrator.Runtime.skill_metadata/1` remain cheap even when skill
directories contain hundreds of entries.

## Data Constraints

### Agent Configuration Constraints

```elixir
# ID constraints
@max_id_length 100
@id_pattern ~r/^[a-z][a-z0-9_]*$/

# Action constraints
@max_actions_per_agent 50
@min_actions_per_agent 1

# Signal constraints
@max_signal_patterns 20
@signal_pattern_regex ~r/^[a-z][a-z0-9._*-]*$/

# State schema constraints
@max_state_fields 50
@max_list_default_length 1000

# Orchestration constraints
@max_specialists_to_spawn 10
```

### Runtime State Constraints

```elixir
# Agent limits
@max_total_agents 100
@max_agents_per_type 50

# Reconciliation limits
@min_reconcile_interval 1_000   # 1 second
@max_reconcile_interval 60_000  # 60 seconds

# Tracking limits
@max_active_reviews 1000
@max_monitors 100

# Performance constraints
@max_spawn_time_ms 5_000
@max_respawn_attempts 5
```

### Agent Instance State Constraints

```elixir
# History constraints
@max_review_history_length 100
@max_learned_patterns 500
@max_scar_tissue_entries 50

# Queue constraints
@max_pending_instructions 1000
@max_pending_results 100

# Timing constraints
@max_action_timeout_ms 30_000
@max_review_timeout_ms 300_000
```

## Data Persistence

### Configuration Persistence

**Format**: Elixir source files (`.exs`)

**Location**: `config/agents.exs` or `config/agents/`

**Versioning**: Git-tracked, human-readable

**Example**:

```elixir
# config/agents.exs
# Version: 2.0
# Last updated: 2025-10-29
# Owner: platform-team

[
  %{
    id: :security_specialist,
    type: :specialist,
    actions: [CheckSQL, CheckXSS, CheckAuth],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]},
    metadata: %{version: "2.0", owner: "security-team"}
  },
  # ... more agents
]
```

### Runtime State Persistence (Optional)

**Format**: ETS or database (for metrics)

**Data Stored**:
```elixir
%{
  agent_id: :security_specialist,
  total_spawns: 5,
  total_signals_processed: 1234,
  total_actions_executed: 3702,
  avg_latency_ms: 45.2,
  last_error: nil,
  uptime_percentage: 99.98
}
```

### Agent State Persistence (Optional)

**Format**: Agent-specific (via Jido state management)

**Data**: Defined by `config.state_schema`

```elixir
# Persisted to configured backend
%{
  review_history: [...],
  learned_patterns: [...],
  scar_tissue: [...]
}
```

## Data Flow Example

### Complete Review Flow

```elixir
# 1. Configuration defines agents
config = %{
  id: :security,
  actions: [CheckSQL],
  signals: %{subscribes: ["review.request"], emits: ["review.result"]}
}

# 2. Runtime loads and spawns
{:ok, pid} = AgentFactory.spawn(config, :synapse_bus, :synapse_registry)

running_agents = %{security: pid}

# 3. Signal arrives
signal = %Jido.Signal{
  type: "review.request",
  data: %{
    review_id: "rev_123",
    diff: "+ SELECT * FROM users WHERE id = '#{input}'"
  }
}

# 4. Agent processes signal
route_handler.(signal)
  → Execute CheckSQL action
  → Get result: {:ok, %{findings: [sql_injection_finding]}}
  → Build result: %{review_id: "rev_123", agent: "security", findings: [...]}
  → Emit signal: type="review.result"

# 5. State update
agent_state = %{
  review_history: [
    %{review_id: "rev_123", timestamp: ~U[...], issues_found: 1}
  ],
  last_review: "rev_123"
}

# 6. Signal emitted
result_signal = %Jido.Signal{
  type: "review.result",
  data: %{review_id: "rev_123", agent: "security", findings: [...]}
}
```

## Type Specifications Summary

### Configuration Types

```elixir
@type agent_config :: Synapse.Orchestrator.AgentConfig.t()
@type agent_id :: Synapse.Orchestrator.AgentConfig.agent_id()
@type agent_type :: Synapse.Orchestrator.AgentConfig.agent_type()
@type signal_config :: %{subscribes: [String.t()], emits: [String.t()]}
@type orchestration_config :: Synapse.Orchestrator.AgentConfig.orchestration()
@type state_schema :: keyword()
```

### Runtime Types

```elixir
@type runtime_state :: Runtime.State.t()
@type running_agents :: %{
  optional(agent_id()) => Synapse.Orchestrator.Runtime.RunningAgent.t()
}
@type monitors :: %{optional(reference()) => agent_id()}
```

### Agent Types

```elixir
@type agent_server_options :: keyword()
@type route_spec :: {String.t(), route_handler()}
@type route_handler :: (Jido.Signal.t() -> {:ok, map()} | {:error, term()})
```

### Signal Types

```elixir
@type review_request :: map()
@type review_result :: map()
@type review_summary :: map()
@type specialist_result :: map()
@type finding :: map()
```

## Data Diagrams

### Configuration → Runtime → Agent

```
AgentConfig (map)
├─ id: :security
├─ type: :specialist
├─ actions: [CheckSQL, CheckXSS]
├─ signals: %{subscribes: [...], emits: [...]}
└─ state_schema: [...]
    ↓ Config.validate/1
    ↓
ValidatedConfig (validated map)
├─ All required fields present
├─ Types validated
└─ Action modules verified
    ↓ Runtime.spawn_agent_from_config/2
    ↓
RunningAgent (tracked in Runtime.State)
├─ agent_id: :security
├─ pid: #PID<0.456.0>
├─ config: ValidatedConfig
├─ monitor_ref: #Reference<...>
└─ spawned_at: DateTime
    ↓ AgentFactory.spawn/3
    ↓
Jido.Agent.Server (running process)
├─ Subscribed to "review.request"
├─ Can execute [CheckSQL, CheckXSS]
├─ State: %{review_history: [...]}
└─ Emits "review.result"
```

### Signal Flow Through Data

```
Review Request Signal
├─ type: "review.request"
├─ data: %{review_id, diff, files_changed, ...}
└─ CloudEvents metadata
    ↓ Matched by route pattern
    ↓
Route Handler Executes
├─ Extracts: review_id, diff, metadata
├─ Executes: All configured actions
└─ Produces: [action_result]
    ↓ result_builder function
    ↓
Result Data Built
├─ review_id: from signal
├─ agent: from config
├─ findings: from action_results
└─ metadata: runtime info
    ↓ emit_result_signal
    ↓
Review Result Signal
├─ type: "review.result"
├─ source: "/synapse/agents/security"
├─ subject: "jido://review/rev_123"
└─ data: result_data
    ↓ Published to bus
    ↓
Coordinator Receives
└─ Aggregates multiple results → Summary
```

## Best Practices

### 1. Configuration Data

**Do**:
- ✅ Use atoms for IDs (`:security_specialist`)
- ✅ Use strings for signal patterns (`"review.request"`)
- ✅ Provide default values in state_schema
- ✅ Document complex functions
- ✅ Keep configs in version control

**Don't**:
- ❌ Use dynamic IDs (must be deterministic)
- ❌ Mix string/atom inconsistently
- ❌ Hardcode environment-specific values
- ❌ Create circular dependencies
- ❌ Exceed constraint limits

### 2. Runtime State

**Do**:
- ✅ Monitor all spawned processes
- ✅ Track spawn counts for debugging
- ✅ Log all reconciliation events
- ✅ Maintain metrics for monitoring

**Don't**:
- ❌ Mutate state outside GenServer
- ❌ Store large data in runtime state
- ❌ Skip cleanup on agent termination
- ❌ Ignore reconciliation failures

### 3. Agent Instance State

**Do**:
- ✅ Use circular buffers for history (limit size)
- ✅ Validate all state updates
- ✅ Initialize with sensible defaults
- ✅ Clean up completed reviews

**Don't**:
- ❌ Store unbounded data (memory leak)
- ❌ Skip validation
- ❌ Mutate state directly
- ❌ Keep stale data indefinitely

## Data Model Evolution

### Versioning Strategy

**Configuration versioning**:

```elixir
# Version 1.0
%{
  id: :security,
  type: :specialist,
  actions: [CheckSQL],
  signals: %{subscribes: ["review.request"], emits: ["review.result"]}
}

# Version 2.0 (backward compatible)
%{
  id: :security,
  type: :specialist,
  actions: [CheckSQL],
  signals: %{subscribes: ["review.request"], emits: ["review.result"]},
  version: "2.0",  # New optional field
  metadata: %{owner: "security-team"}  # New optional field
}
```

**Migration strategy**:
1. Add new optional fields
2. Provide defaults for missing fields
3. Deprecate old fields gradually
4. Support both versions during transition
5. Remove deprecated fields in next major version

### Schema Evolution

**State schema evolution**:

```elixir
# V1 schema
state_schema: [
  review_history: [type: {:list, :map}, default: []]
]

# V2 schema (add new field with default)
state_schema: [
  review_history: [type: {:list, :map}, default: []],
  learned_patterns: [type: {:list, :map}, default: []]  # New field
]

# V3 schema (rename field with migration)
state_schema: [
  reviews: [type: {:list, :map}, default: []],  # Renamed from review_history
  learned_patterns: [type: {:list, :map}, default: []]
]
# Provide migration function to rename review_history → reviews
```

## Debugging Data Structures

### Inspect Configuration

```elixir
# Pretty print config
config
|> IO.inspect(label: "Agent Config", pretty: true, limit: :infinity)

# Validate config
case Config.validate(config) do
  {:ok, validated} ->
    IO.puts("✓ Valid config")
    IO.inspect(validated, label: "Validated")

  {:error, errors} ->
    IO.puts("✗ Invalid config")
    IO.inspect(errors, label: "Errors")
end
```

### Inspect Runtime State

```elixir
# Get current runtime state
runtime_state = :sys.get_state(Synapse.Orchestrator.Runtime)

IO.inspect(runtime_state, label: "Runtime State", pretty: true)

# Check specific agent
agent_id = :security_specialist
pid = runtime_state.running_agents[agent_id]
config = Enum.find(runtime_state.agent_configs, &(&1.id == agent_id))

IO.puts("""
Agent: #{agent_id}
PID: #{inspect(pid)}
Alive: #{Process.alive?(pid)}
Config: #{inspect(config, pretty: true)}
""")
```

### Inspect Agent Instance State

```elixir
# Get agent state via Jido
agent_pid = runtime_state.running_agents[:security_specialist]
agent_state = :sys.get_state(agent_pid)

IO.inspect(agent_state, label: "Agent State", pretty: true)

# Check specific fields
IO.inspect(agent_state.state.review_history, label: "Review History")
IO.inspect(agent_state.state.learned_patterns, label: "Learned Patterns")
```

## See Also

- [Configuration Reference](CONFIGURATION_REFERENCE.md) - Field documentation
- [Architecture](ARCHITECTURE.md) - System design
- [Implementation Guide](IMPLEMENTATION_GUIDE.md) - Building the orchestrator
- [Innovation Summary](INNOVATION_SUMMARY.md) - Why this exists

---

**Understanding the data model is key to working with Synapse Orchestrator.**
