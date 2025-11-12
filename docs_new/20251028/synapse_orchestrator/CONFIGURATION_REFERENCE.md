# Synapse Orchestrator Configuration Reference

**Complete reference for agent configuration options**

## Configuration File Format

Agent configurations are defined as lists of maps in Elixir files:

```elixir
# config/agents.exs
[
  %{
    id: :agent_name,
    type: :specialist,
    # ... more options
  },
  %{
    id: :another_agent,
    type: :orchestrator,
    # ... more options
  }
]
```

All entries are validated against `Synapse.Orchestrator.AgentConfig.schema/0` and
materialised into `%Synapse.Orchestrator.AgentConfig{}` structs at runtime.

## Runtime Options

When starting `Synapse.Orchestrator.Runtime` you can tune behaviour using the
following options:

| Option | Description |
|--------|-------------|
| `:config_source` | Required path or module returning agent configs |
| `:bus` | Signal bus name (defaults to `nil`, allowing each config to supply a bus) |
| `:registry` | Process registry used for agent registration (default `Jido.Registry`) |
| `:reconcile_interval` | Interval in milliseconds between reconciliation passes (default `5_000`) |
| `:skill_directories` | Optional list of directories to scan for skills. Entries augment the default `~/.synapse/skills`, `.synapse/skills/`, and Claude-compatible paths. |

The runtime exposes the discovered skill metadata via
`Synapse.Orchestrator.Runtime.skill_metadata/1`, which returns the same summary
string used for progressive disclosure in prompts.

## Core Fields

### `id` (required)

**Type**: `atom()`
**Description**: Unique identifier for the agent

```elixir
id: :security_specialist
id: :coordinator
id: :my_custom_agent
```

**Rules**:
- Must be unique across all agents
- Used for agent lookup and tracking
- Becomes part of signal source path

### `type` (required)

**Type**: `:specialist | :orchestrator | :custom`
**Description**: Agent archetype that determines behavior pattern

```elixir
type: :specialist     # Action executor
type: :orchestrator   # Multi-agent coordinator
type: :custom         # Custom behavior
```

**Specialist**: Subscribes to signals, executes actions, emits results
**Orchestrator**: Coordinates multiple specialists, aggregates results
**Custom**: User-defined behavior

### `actions`

**Type**: `[module()]`
**Description**: List of action modules the agent can execute

```elixir
actions: [
  Synapse.Actions.Security.CheckSQLInjection,
  Synapse.Actions.Security.CheckXSS,
  Synapse.Actions.Security.CheckAuthIssues
]
```

**Rules**:
- **Required** (non-empty) for `type: :specialist`
- **Optional** for `:orchestrator` and `:custom`; if provided, must be non-empty
- All modules must exist and implement `Jido.Action`
- Validated at configuration load time
- Determines agent capabilities when used

### `signals` (required)

**Type**: `map()`
**Description**: Signal subscription and emission configuration

```elixir
signals: %{
  subscribes: ["review.request", "review.retry"],
  emits: ["review.result", "review.error"]
}
```

**Fields**:
- `subscribes` (required): List of signal patterns to subscribe to
- `emits` (required): List of signal types this agent produces

**Pattern Matching**:
- Exact: `"review.request"`
- Single wildcard: `"review.*"`
- Multi-level wildcard: `"review.**"`
- Multiple patterns: `["pattern1", "pattern2"]`

## Specialist-Specific Fields

### `result_builder` (optional)

**Type**: `(list(), any()) -> map()` or `{module, function, extra_args}`
**Description**: Function to build result from action outputs

```elixir
# Anonymous function
result_builder: fn action_results, review_id ->
  %{
    review_id: review_id,
    agent: "security_specialist",
    findings: extract_findings(action_results)
  }
end

# Module function reference
result_builder: {MyApp.ResultBuilders, :build_security_result, []}

# Default if not provided
# Uses: Synapse.Orchestrator.Behaviors.build_specialist_result/3
```

**Function Signature**:
```elixir
@spec result_builder([{:ok, result} | {:error, reason}], any()) :: map()
```

**Return Value**: Must be a map that will become signal data

## Orchestrator-Specific Fields

### `orchestration` (required for orchestrators)

**Type**: `map()`
**Description**: Orchestration behavior configuration

```elixir
orchestration: %{
  classify_fn: &classify_review/1,
  spawn_specialists: [:security_specialist, :performance_specialist],
  aggregation_fn: &aggregate_results/2,
  fast_path_fn: &handle_fast_path/2  # Optional
}
```

## Custom-Specific Fields

### `custom_handler` (required for custom agents)

**Type**: `(Jido.Signal.t(), map()) -> {:ok, map()} | {:noreply, map()} | {:stop, term(), map()}`
**Description**: Callback invoked for every signal received by a `type: :custom` agent

```elixir
custom_handler: fn signal, state ->
  case signal.type do
    "data.reset" -> {:ok, %{state | cache: %{}}}
    _ -> {:noreply, state}
  end
end
```

**Rules**:
- Required when `type: :custom`
- Receives the incoming `Jido.Signal` and the agent state map
- Must return one of the supported tuples (`{:ok, state}`, `{:noreply, state}`, `{:stop, reason, state}`)
- Can be combined with `actions` to run the standard action pipeline before custom logic

#### `classify_fn` (required)

**Type**: `(map()) -> %{path: atom(), rationale: String.t()}`
**Description**: Determines whether to use fast_path or deep_review

```elixir
classify_fn: fn review_data ->
  if review_data.files_changed > 50 do
    %{path: :deep_review, rationale: "Large change"}
  else
    %{path: :fast_path, rationale: "Small change"}
  end
end
```

#### `spawn_specialists` (required)

**Type**: `[atom()] | (map() -> [atom()])`
**Description**: Which specialists to spawn for deep reviews

```elixir
# Static list
spawn_specialists: [:security_specialist, :performance_specialist]

# Dynamic function
spawn_specialists: fn review_data ->
  specialists = [:security_specialist]

  if "performance" in review_data.labels do
    [:performance_specialist | specialists]
  else
    specialists
  end
end
```

#### `aggregation_fn` (required)

**Type**: `([map()], map()) -> map()`
**Description**: How to aggregate specialist results into summary

```elixir
aggregation_fn: fn specialist_results, review_state ->
  %{
    review_id: review_state.review_id,
    status: :complete,
    findings: Enum.flat_map(specialist_results, & &1.findings),
    metadata: %{
      specialists_resolved: Enum.map(specialist_results, & &1.agent)
    }
  }
end
```

#### `fast_path_fn` (optional)

**Type**: `(Signal.t(), atom()) -> :ok`
**Description**: Handler for fast path reviews (bypasses specialist spawning)

```elixir
fast_path_fn: fn signal, bus ->
  # Emit summary immediately for small changes
  summary = %{
    review_id: signal.data.review_id,
    status: :complete,
    severity: :none,
    findings: [],
    metadata: %{decision_path: :fast_path}
  }

  {:ok, summary_signal} = Jido.Signal.new(%{
    type: "review.summary",
    source: "/synapse/agents/coordinator",
    data: summary
  })

  Jido.Signal.Bus.publish(bus, [summary_signal])
end
```

## Optional Fields

### `state_schema`

**Type**: `keyword()`
**Description**: NimbleOptions schema for agent state

```elixir
state_schema: [
  review_history: [
    type: {:list, :map},
    default: [],
    doc: "Last 100 reviews"
  ],
  learned_patterns: [
    type: {:list, :map},
    default: [],
    doc: "Pattern library"
  ],
  error_count: [
    type: :integer,
    default: 0,
    doc: "Total errors encountered"
  ]
]
```

**Rules**:
- Follows NimbleOptions schema format
- Validated on state updates
- Defaults applied automatically

### `bus`

**Type**: `atom()`
**Default**: `:synapse_bus`
**Description**: Signal bus name to use

```elixir
bus: :my_custom_bus
```

### `registry`

**Type**: `atom()`
**Default**: `:synapse_registry`
**Description**: Agent registry name to use

```elixir
registry: :my_custom_registry
```

### `spawn_condition`

**Type**: `(() -> boolean())`
**Description**: Condition that must be true to spawn agent

```elixir
spawn_condition: fn ->
  Application.get_env(:my_app, :premium_features_enabled, false)
end
```

**Use Case**: Feature flags, environment-specific agents

### `depends_on`

**Type**: `[atom()]`
**Description**: Agents that must be running before this agent starts

```elixir
depends_on: [:security_specialist, :performance_specialist]
```

**Use Case**: Ensure dependencies are available

### `metadata`

**Type**: `map()`
**Description**: Arbitrary metadata for agent

```elixir
metadata: %{
  owner: "security-team",
  version: "2.0",
  criticality: :high,
  cost_per_execution: 0.05
}
```

## Complete Configuration Examples

### Example 1: Minimal Specialist

```elixir
%{
  id: :simple_checker,
  type: :specialist,
  actions: [MyApp.Actions.SimpleCheck],
  signals: %{
    subscribes: ["check.request"],
    emits: ["check.result"]
  }
}
```

### Example 2: Full-Featured Specialist

```elixir
%{
  # Identity
  id: :security_specialist,
  type: :specialist,

  # Capabilities
  actions: [
    Synapse.Actions.Security.CheckSQLInjection,
    Synapse.Actions.Security.CheckXSS,
    Synapse.Actions.Security.CheckAuthIssues
  ],

  # Communication
  signals: %{
    subscribes: ["review.request", "review.recheck"],
    emits: ["review.result", "security.alert"]
  },

  # Behavior
  result_builder: fn results, review_id ->
    %{
      review_id: review_id,
      agent: "security_specialist",
      confidence: calculate_confidence(results),
      findings: extract_findings(results),
      should_escalate: has_high_severity?(results),
      metadata: %{
        path: :deep_review,
        actions_run: length(results)
      }
    }
  end,

  # State management
  state_schema: [
    review_history: [type: {:list, :map}, default: []],
    learned_patterns: [type: {:list, :map}, default: []],
    scar_tissue: [type: {:list, :map}, default: []]
  ],

  # Infrastructure
  bus: :synapse_bus,
  registry: :synapse_registry,

  # Runtime conditions
  spawn_condition: fn ->
    Application.get_env(:synapse, :security_checks_enabled, true)
  end,

  # Metadata
  metadata: %{
    owner: "security-team",
    sla_ms: 100,
    criticality: :high
  }
}
```

### Example 3: Orchestrator

```elixir
%{
  # Identity
  id: :coordinator,
  type: :orchestrator,

  # Core actions
  actions: [
    Synapse.Actions.Review.ClassifyChange,
    Synapse.Actions.Review.GenerateSummary
  ],

  # Communication
  signals: %{
    subscribes: ["review.request", "review.result"],
    emits: ["review.summary", "review.escalated"]
  },

  # Orchestration logic
  orchestration: %{
    # Classification
    classify_fn: fn review_data ->
      cond do
        review_data.files_changed > 100 ->
          %{path: :deep_review, rationale: "Very large change"}

        "security" in review_data.labels ->
          %{path: :deep_review, rationale: "Security-sensitive"}

        review_data.intent == "hotfix" ->
          %{path: :fast_path, rationale: "Urgent hotfix"}

        true ->
          %{path: :fast_path, rationale: "Standard review"}
      end
    end,

    # Which specialists to spawn
    spawn_specialists: fn review_data ->
      base = [:security_specialist]

      specialists = if "performance" in review_data.labels do
        [:performance_specialist | base]
      else
        base
      end

      specialists
    end,

    # How to aggregate results
    aggregation_fn: fn specialist_results, review_state ->
      all_findings = Enum.flat_map(specialist_results, & &1.findings)

      %{
        review_id: review_state.review_id,
        status: :complete,
        severity: max_severity(all_findings),
        findings: all_findings,
        recommendations: extract_recommendations(all_findings),
        metadata: %{
          decision_path: review_state.classification_path,
          specialists_resolved: Enum.map(specialist_results, & &1.agent),
          duration_ms: review_state.duration_ms
        }
      }
    end,

    # Fast path handler
    fast_path_fn: fn signal, bus ->
      summary = %{
        review_id: signal.data.review_id,
        status: :complete,
        severity: :none,
        findings: [],
        metadata: %{decision_path: :fast_path}
      }

      {:ok, summary_signal} = Jido.Signal.new(%{
        type: "review.summary",
        source: "/synapse/agents/coordinator",
        data: summary
      })

      Jido.Signal.Bus.publish(bus, [summary_signal])
    end
  },

  # State tracking
  state_schema: [
    review_count: [type: :integer, default: 0],
    active_reviews: [type: :map, default: %{}],
    fast_path_count: [type: :integer, default: 0],
    deep_review_count: [type: :integer, default: 0]
  ],

  # Dependencies
  depends_on: [:security_specialist, :performance_specialist]
}
```

### Example 4: Conditional Agent

```elixir
%{
  id: :premium_security_scanner,
  type: :specialist,

  actions: [
    Synapse.Actions.Security.AdvancedThreatDetection,
    Synapse.Actions.Security.ZeroDayScanner
  ],

  signals: %{
    subscribes: ["review.request"],
    emits: ["review.advanced_security"]
  },

  # Only spawn in production with premium feature flag
  spawn_condition: fn ->
    Application.get_env(:synapse, :environment) == :production and
    Application.get_env(:synapse, :premium_features, false)
  end,

  metadata: %{
    tier: :premium,
    cost_per_execution: 0.50
  }
}
```

## Configuration Patterns

### Pattern 1: Agent Template

Define reusable configuration templates:

```elixir
# lib/my_app/agent_templates.ex
defmodule MyApp.AgentTemplates do
  def specialist_template do
    %{
      type: :specialist,
      signals: %{
        subscribes: ["review.request"],
        emits: ["review.result"]
      },
      result_builder: &Synapse.Orchestrator.Behaviors.build_specialist_result/3,
      state_schema: [
        review_history: [type: {:list, :map}, default: []]
      ]
    }
  end

  def security_specialist(actions) do
    Map.merge(specialist_template(), %{
      id: :security_specialist,
      actions: actions,
      metadata: %{domain: :security}
    })
  end

  def performance_specialist(actions) do
    Map.merge(specialist_template(), %{
      id: :performance_specialist,
      actions: actions,
      metadata: %{domain: :performance}
    })
  end
end

# config/agents.exs
alias MyApp.AgentTemplates

[
  AgentTemplates.security_specialist([CheckSQL, CheckXSS]),
  AgentTemplates.performance_specialist([CheckComplexity, CheckMemory])
]
```

### Pattern 2: Environment-Specific Configs

```elixir
# config/agents/common.exs
defmodule MyApp.CommonAgents do
  def base_specialist(id, actions) do
    %{
      id: id,
      type: :specialist,
      actions: actions,
      signals: %{subscribes: ["review.request"], emits: ["review.result"]}
    }
  end
end

# config/agents/dev.exs
import MyApp.CommonAgents

[
  base_specialist(:security, [CheckSQL]),  # Minimal in dev
  base_specialist(:performance, [CheckComplexity])
]

# config/agents/prod.exs
import MyApp.CommonAgents

[
  base_specialist(:security, [CheckSQL, CheckXSS, CheckAuth, CheckCrypto]),
  base_specialist(:performance, [CheckComplexity, CheckMemory, ProfileHotPath]),
  # Additional agents in prod
  %{
    id: :compliance_checker,
    type: :specialist,
    actions: [CheckGDPR, CheckSOC2],
    signals: %{subscribes: ["review.request"], emits: ["compliance.result"]}
  }
]
```

### Pattern 3: Dynamic Agent Configuration

```elixir
# config/agents.exs
defmodule DynamicAgents do
  def agent_configs do
    # Base agents always present
    base = [
      security_agent(),
      performance_agent()
    ]

    # Add premium agents if feature enabled
    premium = if premium_enabled?() do
      [premium_security_agent(), ml_analyzer_agent()]
    else
      []
    end

    # Add region-specific agents
    regional = regional_agents()

    base ++ premium ++ regional
  end

  defp premium_enabled? do
    Application.get_env(:synapse, :premium_tier, false)
  end

  defp security_agent do
    %{id: :security, type: :specialist, ...}
  end

  defp regional_agents do
    regions = Application.get_env(:synapse, :regions, [:us_east])

    Enum.map(regions, fn region ->
      %{
        id: :"compliance_#{region}",
        type: :specialist,
        actions: compliance_actions_for_region(region),
        signals: %{subscribes: ["review.request"], emits: ["compliance.result"]}
      }
    end)
  end
end

# Use module for config
DynamicAgents.agent_configs()
```

## Validation Rules

### Configuration Validation

All configs are validated at load time:

```elixir
# Required field validation
{:error, "Required key :id not found"} = Config.validate(%{
  type: :specialist,
  actions: [],
  signals: %{subscribes: [], emits: []}
})

# Type validation
{:error, "Invalid type: must be one of [:specialist, :orchestrator, :custom]"} =
  Config.validate(%{
    id: :test,
    type: :invalid,
    actions: [],
    signals: %{subscribes: [], emits: []}
  })

# Action module validation
{:error, "Actions not found: [NonExistent.Module]"} =
  Config.validate(%{
    id: :test,
    type: :specialist,
    actions: [NonExistent.Module],
    signals: %{subscribes: [], emits: []}
  })
```

### Runtime Validation

Additional validation when adding agents dynamically:

```elixir
# Check for ID conflicts
{:error, :agent_already_exists} = Runtime.add_agent(runtime_pid, %{
  id: :security_specialist,  # Already running
  type: :specialist,
  actions: [SomeAction],
  signals: %{subscribes: ["test"], emits: ["result"]}
})

# Validate configuration before adding
case AgentConfig.new(config_map) do
  {:ok, validated_config} ->
    Runtime.add_agent(runtime_pid, validated_config)

  {:error, validation_error} ->
    # Handle validation error
    Logger.error("Invalid config: #{inspect(validation_error)}")
end
```

## Configuration Best Practices

### 1. Organization

```elixir
# Group by domain
# config/agents/security.exs
[security_specialist(), compliance_checker()]

# config/agents/performance.exs
[performance_specialist(), profiler()]

# config/agents/orchestration.exs
[coordinator(), aggregator()]

# config/agents.exs (main file)
security_agents() ++ performance_agents() ++ orchestration_agents()
```

### 2. Documentation

```elixir
%{
  id: :security_specialist,
  type: :specialist,

  # Document purpose
  metadata: %{
    description: "Detects security vulnerabilities in code changes",
    owner: "security-team@company.com",
    sla_ms: 100,
    cost_model: "per-review"
  },

  actions: [
    # List what each action does
    CheckSQLInjection,     # Detects SQL injection patterns
    CheckXSS,              # Detects XSS vulnerabilities
    CheckAuthIssues        # Detects auth bypass attempts
  ]
}
```

### 3. Validation

```elixir
# Always validate configs before deploying
defmodule MyApp.ConfigValidator do
  def validate_production_config do
    case Synapse.Orchestrator.Config.load("config/agents/prod.exs") do
      {:ok, configs} ->
        # Additional business logic validation
        validate_sla_requirements(configs)
        validate_cost_constraints(configs)
        validate_dependencies(configs)

      {:error, reason} ->
        raise "Invalid production config: #{reason}"
    end
  end
end
```

### 4. Testing

```elixir
# Test configurations in your test suite
defmodule MyApp.AgentConfigTest do
  use ExUnit.Case

  test "production config is valid" do
    assert {:ok, configs} = Config.load("config/agents/prod.exs")
    assert length(configs) >= 3
  end

  test "all agents have required fields" do
    {:ok, configs} = Config.load("config/agents.exs")

    for config <- configs do
      assert config.id
      assert config.type
      assert config.actions != []
      assert config.signals.subscribes != []
      assert config.signals.emits != []
    end
  end

  test "no duplicate agent IDs" do
    {:ok, configs} = Config.load("config/agents.exs")

    ids = Enum.map(configs, & &1.id)
    unique_ids = Enum.uniq(ids)

    assert length(ids) == length(unique_ids), "Duplicate agent IDs found"
  end
end
```

## Configuration Schema Reference

### Full NimbleOptions Schema

```elixir
@schema [
  id: [
    type: :atom,
    required: true,
    doc: "Unique agent identifier"
  ],
  type: [
    type: {:in, [:specialist, :orchestrator, :custom]},
    required: true,
    doc: "Agent archetype"
  ],
  actions: [
    type: {:list, :atom},
    required: true,
    doc: "Action modules the agent can execute"
  ],
  signals: [
    type: :map,
    required: true,
    keys: [
      subscribes: [type: {:list, :string}, required: true],
      emits: [type: {:list, :string}, required: true]
    ],
    doc: "Signal routing configuration"
  ],
  result_builder: [
    type: {:or, [:mfa, {:fun, 2}]},
    doc: "Result building function"
  ],
  orchestration: [
    type: :map,
    keys: [
      classify_fn: [type: {:or, [:mfa, {:fun, 1}]}, required: true],
      spawn_specialists: [type: {:or, [{:list, :atom}, {:fun, 1}]}, required: true],
      aggregation_fn: [type: {:or, [:mfa, {:fun, 2}]}, required: true],
      fast_path_fn: [type: {:or, [:mfa, {:fun, 2}]}]
    ],
    doc: "Orchestrator configuration"
  ],
  state_schema: [
    type: :keyword_list,
    default: [],
    doc: "NimbleOptions schema for agent state"
  ],
  bus: [
    type: :atom,
    default: :synapse_bus,
    doc: "Signal bus name"
  ],
  registry: [
    type: :atom,
    default: :synapse_registry,
    doc: "Agent registry name"
  ],
  spawn_condition: [
    type: {:fun, 0},
    doc: "Condition that must be true to spawn agent"
  ],
  depends_on: [
    type: {:list, :atom},
    default: [],
    doc: "Agent IDs that must exist before spawning"
  ],
  metadata: [
    type: :map,
    default: %{},
    doc: "Arbitrary agent metadata"
  ]
]
```

## Troubleshooting

### Common Configuration Errors

**Error**: "Required key :id not found"
**Solution**: Add `id: :agent_name` to configuration

**Error**: "Actions not found: [Module]"
**Solution**: Ensure action module exists and is compiled

**Error**: "Invalid type"
**Solution**: Use `:specialist`, `:orchestrator`, or `:custom`

**Error**: "Invalid signal pattern"
**Solution**: Check signal pattern syntax (use strings, not atoms)

### Debug Configuration Loading

```elixir
# Enable debug logging
Logger.configure(level: :debug)

# Load config with detailed output
case Config.load("config/agents.exs") do
  {:ok, configs} ->
    IO.inspect(configs, label: "Loaded Configs")

  {:error, reason} ->
    IO.inspect(reason, label: "Config Error")
end
```

## See Also

- [Orchestrator Vision](ORCHESTRATOR_VISION.md) - Why this exists
- [Architecture](ARCHITECTURE.md) - How it works
- [Implementation Guide](IMPLEMENTATION_GUIDE.md) - How to build it
- [Migration Guide](MIGRATION_GUIDE.md) - How to migrate existing agents

---

**Complete, validated configuration is the foundation of reliable orchestration.**
