# Synapse Orchestrator: Configuration-Driven Multi-Agent Systems

**Status**: Design Document
**Date**: 2025-10-29
**Innovation**: Puppet for Jido - Declarative Agent Orchestration

## The Problem

We just built 3 GenServer agents (~900 lines of code):
- `SecurityAgentServer` (264 lines) - 95% boilerplate
- `PerformanceAgentServer` (264 lines) - identical pattern to SecurityAgent
- `CoordinatorAgentServer` (384 lines) - orchestration boilerplate

**The Pain**: Every new agent type requires:
1. Writing a GenServer module (100+ lines)
2. Implementing signal subscription logic
3. Handling action execution
4. Managing state updates
5. Writing tests for all the boilerplate
6. Duplicating patterns across agents

**The Insight**: All these agents follow **identical patterns** that Jido already provides. We're just wrapping Jido primitives with repetitive GenServer code.

## The Innovation: Configuration-Driven Agents

**Instead of code, we write configuration:**

```elixir
# config/agents.exs
[
  # Security specialist agent
  %{
    id: :security_specialist,
    type: :specialist,

    # What it does
    actions: [
      Synapse.Actions.Security.CheckSQLInjection,
      Synapse.Actions.Security.CheckXSS,
      Synapse.Actions.Security.CheckAuthIssues
    ],

    # How it communicates
    signals: %{
      subscribes: ["review.request"],
      emits: ["review.result"]
    },

    # Agent behavior
    result_builder: fn results, review_id ->
      %{
        review_id: review_id,
        agent: "security_specialist",
        confidence: avg_confidence(results),
        findings: flat_map_findings(results),
        should_escalate: any_high_severity?(results)
      }
    end,

    # State management (optional)
    state_schema: [
      review_history: [type: {:list, :map}, default: []],
      learned_patterns: [type: {:list, :map}, default: []],
      scar_tissue: [type: {:list, :map}, default: []]
    ]
  },

  # Performance specialist agent
  %{
    id: :performance_specialist,
    type: :specialist,

    actions: [
      Synapse.Actions.Performance.CheckComplexity,
      Synapse.Actions.Performance.CheckMemoryUsage,
      Synapse.Actions.Performance.ProfileHotPath
    ],

    signals: %{
      subscribes: ["review.request"],
      emits: ["review.result"]
    },

    result_builder: fn results, review_id ->
      %{
        review_id: review_id,
        agent: "performance_specialist",
        confidence: avg_confidence(results),
        findings: flat_map_findings(results),
        should_escalate: any_high_severity?(results)
      }
    end
  },

  # Coordinator agent
  %{
    id: :coordinator,
    type: :orchestrator,

    actions: [
      Synapse.Actions.Review.ClassifyChange,
      Synapse.Actions.Review.GenerateSummary
    ],

    signals: %{
      subscribes: ["review.request", "review.result"],
      emits: ["review.summary"]
    },

    # Orchestration behavior
    orchestration: %{
      classify_fn: &Synapse.Orchestrator.Behaviors.classify_review/1,
      spawn_specialists: [:security_specialist, :performance_specialist],
      aggregation_fn: &Synapse.Orchestrator.Behaviors.aggregate_results/2
    },

    state_schema: [
      review_count: [type: :integer, default: 0],
      active_reviews: [type: :map, default: %{}]
    ]
  }
]
```

**That's it.** No GenServer code. No boilerplate. Just configuration.

## The Architecture

```
┌─────────────────────────────────────────┐
│   Agent Configuration (agents.exs)      │
│   - Declarative agent definitions       │
│   - Signal routing rules                │
│   - Action mappings                     │
│   - Behavior specifications             │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Synapse.Orchestrator                  │
│   (Compile-time + Runtime Manager)      │
│                                         │
│   Compile-time:                         │
│   - Validates configurations            │
│   - Generates agent specs               │
│   - Creates supervision trees           │
│                                         │
│   Runtime:                              │
│   - Spawns agents from config           │
│   - Manages agent lifecycle             │
│   - Routes signals automatically        │
│   - Monitors and restarts failed agents │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Jido.Agent.Server (per agent)        │
│   - Started from configuration          │
│   - Subscribes to configured signals    │
│   - Executes configured actions         │
│   - Emits configured results            │
└─────────────────────────────────────────┘
```

## Core Components

### 1. Synapse.Orchestrator.Config

**Purpose**: Define and validate agent configurations

```elixir
defmodule Synapse.Orchestrator.Config do
  @moduledoc """
  Configuration schema for declarative agent systems.

  Defines agents as pure data structures that the orchestrator
  uses to spawn and manage Jido.Agent.Server instances.
  """

  use NimbleOptions,
    schema: [
      id: [
        type: :atom,
        required: true,
        doc: "Unique agent identifier"
      ],
      type: [
        type: {:in, [:specialist, :orchestrator, :coordinator, :custom]},
        required: true,
        doc: "Agent archetype"
      ],
      actions: [
        type: {:list, :atom},
        required: true,
        doc: "List of action modules this agent can execute"
      ],
      signals: [
        type: :map,
        required: true,
        keys: [
          subscribes: [type: {:list, :string}, required: true],
          emits: [type: {:list, :string}, required: true]
        ],
        doc: "Signal subscription and emission configuration"
      ],
      result_builder: [
        type: {:fun, 2},
        doc: "Function to build result from action outputs: (results, review_id) -> map"
      ],
      orchestration: [
        type: :map,
        doc: "Orchestrator-specific configuration"
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
      ]
    ]

  @doc """
  Validates an agent configuration.

  ## Examples

      iex> Config.validate(%{
      ...>   id: :my_agent,
      ...>   type: :specialist,
      ...>   actions: [MyAction],
      ...>   signals: %{subscribes: ["input"], emits: ["output"]}
      ...> })
      {:ok, validated_config}
  """
  def validate(config) do
    NimbleOptions.validate(config, schema())
  end

  @doc """
  Loads agent configurations from a file or module.

  ## Examples

      # From file
      {:ok, configs} = Config.load("config/agents.exs")

      # From module
      {:ok, configs} = Config.load(MyApp.AgentConfigs)
  """
  def load(source) when is_binary(source) do
    # Load from file
    case File.read(source) do
      {:ok, content} ->
        {configs, _} = Code.eval_string(content)
        validate_all(configs)

      {:error, reason} ->
        {:error, "Failed to load config: #{reason}"}
    end
  end

  def load(module) when is_atom(module) do
    # Load from module
    configs = apply(module, :agent_configs, [])
    validate_all(configs)
  end

  defp validate_all(configs) when is_list(configs) do
    results = Enum.map(configs, &validate/1)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {valid, []} ->
        {:ok, Enum.map(valid, fn {:ok, config} -> config end)}

      {_, errors} ->
        {:error, errors}
    end
  end
end
```

### 2. Synapse.Orchestrator.Runtime

**Purpose**: Spawn and manage agents from configurations

```elixir
defmodule Synapse.Orchestrator.Runtime do
  @moduledoc """
  Runtime manager that spawns and manages agents from configurations.

  This is the "Puppet" layer - it maintains the desired state defined
  in configuration by continuously reconciling actual vs desired agent state.
  """

  use GenServer
  require Logger

  alias Synapse.Orchestrator.{Config, AgentFactory}

  defstruct [
    :config_source,
    :agent_configs,
    :running_agents,
    :bus,
    :registry,
    :reconcile_interval
  ]

  @doc """
  Starts the orchestrator runtime.

  ## Options

    * `:config_source` - File path or module with agent configs
    * `:bus` - Signal bus name (default: :synapse_bus)
    * `:registry` - Agent registry name (default: :synapse_registry)
    * `:reconcile_interval` - How often to check desired state (default: 5000ms)

  ## Examples

      {:ok, pid} = Runtime.start_link(
        config_source: "config/agents.exs",
        reconcile_interval: 10_000
      )
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config_source = Keyword.fetch!(opts, :config_source)

    # Load and validate configs
    {:ok, agent_configs} = Config.load(config_source)

    state = %__MODULE__{
      config_source: config_source,
      agent_configs: agent_configs,
      running_agents: %{},
      bus: Keyword.get(opts, :bus, :synapse_bus),
      registry: Keyword.get(opts, :registry, :synapse_registry),
      reconcile_interval: Keyword.get(opts, :reconcile_interval, 5000)
    }

    # Start initial reconciliation
    send(self(), :reconcile)

    Logger.info("Orchestrator started with #{length(agent_configs)} agent configs")

    {:ok, state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    # Reconcile desired vs actual state
    new_state = reconcile_agents(state)

    # Schedule next reconciliation
    Process.send_after(self(), :reconcile, state.reconcile_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle agent termination
    Logger.warning("Agent process terminated", pid: inspect(pid), reason: reason)

    # Reconciliation will restart it
    {:noreply, state}
  end

  ## Private Functions

  defp reconcile_agents(state) do
    Logger.debug("Reconciling agents...")

    # For each configured agent
    Enum.reduce(state.agent_configs, state, fn config, acc_state ->
      reconcile_single_agent(config, acc_state)
    end)
  end

  defp reconcile_single_agent(config, state) do
    agent_id = config.id

    case Map.get(state.running_agents, agent_id) do
      nil ->
        # Agent not running - spawn it
        spawn_agent_from_config(config, state)

      pid when is_pid(pid) ->
        # Agent exists - verify it's healthy
        if Process.alive?(pid) do
          state  # All good
        else
          # Dead process - respawn
          Logger.info("Respawning dead agent", agent_id: agent_id)
          spawn_agent_from_config(config, state)
        end
    end
  end

  defp spawn_agent_from_config(config, state) do
    Logger.info("Spawning agent from config", agent_id: config.id)

    # Use AgentFactory to create Jido.Agent.Server from config
    case AgentFactory.spawn(config, state.bus, state.registry) do
      {:ok, pid} ->
        # Monitor the agent
        Process.monitor(pid)

        # Track running agent
        running_agents = Map.put(state.running_agents, config.id, pid)
        %{state | running_agents: running_agents}

      {:error, reason} ->
        Logger.error("Failed to spawn agent",
          agent_id: config.id,
          reason: inspect(reason)
        )
        state
    end
  end
end
```

### 3. Synapse.Orchestrator.AgentFactory

**Purpose**: Transform configurations into running Jido.Agent.Server instances

```elixir
defmodule Synapse.Orchestrator.AgentFactory do
  @moduledoc """
  Factory that creates Jido.Agent.Server instances from configurations.

  This is where configuration becomes reality - taking declarative
  agent definitions and spawning actual running processes.
  """

  require Logger

  @doc """
  Spawns a Jido.Agent.Server from configuration.

  ## Configuration Types

  ### Specialist Agent

  Simple action execution agents that subscribe to signals,
  run actions, and emit results.

      %{
        id: :security_specialist,
        type: :specialist,
        actions: [Action1, Action2],
        signals: %{subscribes: ["input"], emits: ["output"]},
        result_builder: &build_result/2
      }

  ### Orchestrator Agent

  Coordination agents that spawn other agents and aggregate results.

      %{
        id: :coordinator,
        type: :orchestrator,
        orchestration: %{
          classify_fn: &classify/1,
          spawn_specialists: [:security, :performance],
          aggregation_fn: &aggregate/2
        }
      }
  """
  def spawn(config, bus, registry) do
    case config.type do
      :specialist ->
        spawn_specialist(config, bus, registry)

      :orchestrator ->
        spawn_orchestrator(config, bus, registry)

      :custom ->
        spawn_custom(config, bus, registry)
    end
  end

  ## Specialist Agent Factory

  defp spawn_specialist(config, bus, _registry) do
    # Build Jido.Agent.Server options from config
    opts = [
      id: to_string(config.id),
      bus: bus,

      # Register actions
      actions: config.actions,

      # Build routes for signal subscriptions
      routes: build_specialist_routes(config),

      # Configure state if specified
      schema: config[:state_schema] || []
    ]

    # Start the Jido.Agent.Server
    # This is the key - we're using Jido's infrastructure, not writing our own
    Jido.Agent.Server.start_link(opts)
  end

  defp build_specialist_routes(config) do
    # Convert signal subscriptions to Jido routes
    Enum.map(config.signals.subscribes, fn signal_pattern ->
      {
        signal_pattern,
        build_specialist_instruction(config)
      }
    end)
  end

  defp build_specialist_instruction(config) do
    # Create instruction that runs all actions and emits result
    %{
      on_match: fn signal, agent_state ->
        # Execute all configured actions
        results = Enum.map(config.actions, fn action ->
          Jido.Exec.run(action, signal.data, %{})
        end)

        # Extract review_id from signal
        review_id = get_in(signal.data, [:review_id])

        # Build result using configured builder
        result_data = config.result_builder.(results, review_id)

        # Emit result signal
        {:ok, result_signal} = Jido.Signal.new(%{
          type: hd(config.signals.emits),
          source: "/synapse/agents/#{config.id}",
          subject: "jido://review/#{review_id}",
          data: result_data
        })

        Jido.Signal.Bus.publish(bus, [result_signal])

        # Update agent state (history tracking)
        updated_state = update_specialist_state(agent_state, review_id, result_data)
        {:ok, updated_state}
      end
    }
  end

  ## Orchestrator Agent Factory

  defp spawn_orchestrator(config, bus, registry) do
    orchestration = config.orchestration

    opts = [
      id: to_string(config.id),
      bus: bus,
      registry: registry,
      actions: config.actions,
      schema: config[:state_schema] || [],

      # Build routes for orchestration
      routes: build_orchestrator_routes(config, bus, registry)
    ]

    Jido.Agent.Server.start_link(opts)
  end

  defp build_orchestrator_routes(config, bus, registry) do
    orchestration = config.orchestration

    [
      # Route: review.request
      {
        "review.request",
        %{
          on_match: fn signal, agent_state ->
            # 1. Classify the review
            classification = orchestration.classify_fn.(signal.data)

            case classification.path do
              :fast_path ->
                # Emit summary immediately
                emit_fast_path_summary(signal, bus)
                {:ok, agent_state}

              :deep_review ->
                # Spawn specialists and track review
                spawn_specialists_from_config(
                  orchestration.spawn_specialists,
                  registry,
                  bus
                )

                # Track review in state
                updated_state = start_review_tracking(
                  agent_state,
                  signal,
                  orchestration.spawn_specialists
                )

                # Republish for specialists
                republish_signal(signal, bus)

                {:ok, updated_state}
            end
          end
        }
      },

      # Route: review.result
      {
        "review.result",
        %{
          on_match: fn signal, agent_state ->
            review_id = signal.data.review_id

            # Add result to tracking
            updated_state = add_specialist_result(agent_state, review_id, signal.data)

            # Check if all specialists responded
            case check_review_complete(updated_state, review_id) do
              {:complete, review_state} ->
                # Aggregate and emit summary
                summary = orchestration.aggregation_fn.(
                  review_state.results,
                  review_state
                )

                emit_summary_signal(summary, bus)

                # Clean up tracking
                final_state = complete_review_tracking(updated_state, review_id)
                {:ok, final_state}

              {:pending, _} ->
                {:ok, updated_state}
            end
          end
        }
      }
    ]
  end
end
```

### 4. Synapse.Orchestrator.Behaviors

**Purpose**: Reusable behavior functions for common patterns

```elixir
defmodule Synapse.Orchestrator.Behaviors do
  @moduledoc """
  Common behavior implementations for agent configurations.

  These functions can be referenced in agent configs to provide
  standard behaviors without writing custom code.
  """

  ## Classification Behaviors

  def classify_review(review_data) do
    cond do
      review_data.files_changed > 50 ->
        %{path: :deep_review, rationale: "Large change requires full review"}

      "security" in review_data.labels or "performance" in review_data.labels ->
        %{path: :deep_review, rationale: "Critical labels present"}

      review_data.intent == "hotfix" ->
        %{path: :fast_path, rationale: "Hotfix - quick review"}

      true ->
        %{path: :fast_path, rationale: "Small change, low risk"}
    end
  end

  ## Result Building Behaviors

  def build_specialist_result(action_results, review_id, agent_name) do
    all_findings = Enum.flat_map(action_results, fn
      {:ok, result} -> result.findings
      {:error, _} -> []
    end)

    avg_confidence = calculate_avg_confidence(action_results)

    %{
      review_id: review_id,
      agent: agent_name,
      confidence: avg_confidence,
      findings: all_findings,
      should_escalate: Enum.any?(all_findings, &(&1.severity == :high)),
      metadata: %{
        runtime_ms: 0,  # TODO: track actual runtime
        path: :deep_review,
        actions_run: Enum.map(action_results, fn {_, result} -> result end)
      }
    }
  end

  ## Aggregation Behaviors

  def aggregate_results(specialist_results, review_state) do
    all_findings = Enum.flat_map(specialist_results, & &1.findings)

    %{
      review_id: review_state.review_id,
      status: :complete,
      severity: calculate_max_severity(all_findings),
      findings: all_findings,
      recommendations: extract_recommendations(all_findings),
      escalations: [],
      metadata: %{
        decision_path: review_state.classification_path,
        specialists_resolved: Enum.map(specialist_results, & &1.agent),
        duration_ms: calculate_duration(review_state)
      }
    }
  end

  ## Helper Functions

  defp calculate_avg_confidence(results) do
    # Implementation
    0.8
  end

  defp calculate_max_severity(findings) do
    # Implementation
    :medium
  end

  defp extract_recommendations(findings) do
    # Implementation
    []
  end

  defp calculate_duration(review_state) do
    # Implementation
    100
  end
end
```

### 5. Usage Example

**Application startup:**

```elixir
defmodule Synapse.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Core infrastructure
      {Jido.Signal.Bus, name: :synapse_bus},
      {Synapse.AgentRegistry, name: :synapse_registry},

      # THE INNOVATION: Single orchestrator replaces all agent modules
      {Synapse.Orchestrator.Runtime,
        config_source: "config/agents.exs",
        bus: :synapse_bus,
        registry: :synapse_registry,
        reconcile_interval: 10_000
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**That's the entire startup.** No SecurityAgentServer, no PerformanceAgentServer, no CoordinatorAgentServer modules. Just configurations.

## The Baseline Metric

**Before (Current Implementation):**
- 3 GenServer modules (~900 lines)
- 3 test files (~800 lines)
- ~1,700 total lines of code

**After (Configuration-Driven):**
- 1 config file (~150 lines)
- 1 orchestrator runtime (~400 lines, reusable)
- 1 factory (~300 lines, reusable)
- ~850 total lines (50% reduction)

**For each new agent type:**
- Before: ~300 lines of code + tests
- After: ~30 lines of configuration

**10x reduction in boilerplate per agent.**

## Advanced Features

### 1. Hot Reload Configuration

```elixir
# Trigger immediate reconciliation (reloads config from source)
Synapse.Orchestrator.Runtime.reload(runtime_pid)

# Add new agent at runtime
{:ok, agent_pid} = Synapse.Orchestrator.Runtime.add_agent(runtime_pid, %{
  id: :new_specialist,
  type: :specialist,
  actions: [NewAction],
  signals: %{subscribes: ["new.signal"], emits: ["new.result"]}
})

# Remove agent
:ok = Synapse.Orchestrator.Runtime.remove_agent(runtime_pid, :old_specialist)
```

### 2. Agent Templates

```elixir
# Define reusable templates
templates = %{
  specialist: %{
    type: :specialist,
    signals: %{
      subscribes: ["review.request"],
      emits: ["review.result"]
    },
    result_builder: &Synapse.Orchestrator.Behaviors.build_specialist_result/3
  }
}

# Use template with overrides
security_agent = Map.merge(templates.specialist, %{
  id: :security_specialist,
  actions: [CheckSQL, CheckXSS, CheckAuth]
})
```

### 3. Conditional Agent Spawning

```elixir
# Spawn agents based on runtime conditions
%{
  id: :premium_specialist,
  type: :specialist,
  spawn_condition: fn ->
    Application.get_env(:synapse, :premium_features_enabled, false)
  end,
  actions: [PremiumAction1, PremiumAction2]
}
```

### 4. Agent Dependencies

```elixir
# Express agent dependencies
%{
  id: :aggregator,
  type: :custom,
  depends_on: [:security_specialist, :performance_specialist],
  signals: %{
    subscribes: ["review.result"],
    emits: ["review.aggregated"]
  }
}
```

## Benefits of This Approach

### 1. Radical Simplification
- **No boilerplate GenServer code**
- **No duplicated patterns**
- **No manual signal subscription**
- **No lifecycle management code**

### 2. Dynamic Reconfiguration
- **Add agents without code deploys**
- **Modify routing at runtime**
- **A/B test agent configurations**
- **Feature flags for agents**

### 3. Declarative Reasoning
- **See all agents at a glance**
- **Understand system topology from config**
- **Version control agent behavior**
- **Audit changes easily**

### 4. Testing Simplification
- **Test configs, not GenServers**
- **Mock agents via config**
- **Simulate topologies easily**
- **Property-based config testing**

### 5. Jido Integration
- **Leverages Jido.Agent.Server**
- **Uses Jido.Signal.Router**
- **Reuses Jido.Exec**
- **No reimplementation**

## Migration Path

### Phase 1: Build the Orchestrator
1. Implement `Synapse.Orchestrator.Config`
2. Implement `Synapse.Orchestrator.Runtime`
3. Implement `Synapse.Orchestrator.AgentFactory`
4. Implement `Synapse.Orchestrator.Behaviors`

### Phase 2: Convert Existing Agents
1. Extract SecurityAgentServer config
2. Extract PerformanceAgentServer config
3. Extract CoordinatorAgentServer config
4. Test equivalence

### Phase 3: Replace Implementation
1. Remove GenServer modules
2. Update Application startup
3. Update tests
4. Verify Stage 2 demo still works

### Phase 4: Extend
1. Add hot reload
2. Add templates
3. Add conditional spawning
4. Add agent discovery API

## Comparison to Alternatives

### vs. Hardcoded GenServers (Current)
- ✅ Less code
- ✅ More flexible
- ✅ Easier to reason about
- ✅ Dynamic reconfiguration

### vs. Kubernetes
- Similar declarative model
- Focused on agents, not containers
- Tighter Jido integration
- Simpler operational model

### vs. Ansible
- Puppet-style continuous reconciliation
- Not imperative playbooks
- Always maintains desired state
- Self-healing

## The Innovation

**What makes this special:**

1. **It's a compile-time library, not a framework**
   - Pure Elixir modules
   - No magic macros
   - Clear boundaries
   - Easy to understand

2. **It's purpose-built for Jido**
   - Leverages Jido patterns
   - Doesn't reinvent wheels
   - Extends, doesn't replace

3. **It's declarative orchestration**
   - Define what, not how
   - System maintains state
   - Continuous reconciliation
   - Puppet for agents

4. **It generalizes our implementation**
   - Everything we built becomes config
   - 900 lines → 150 lines
   - Future agents: 30 lines each
   - 10x productivity gain

## Next Steps

1. **Prototype the orchestrator** (2-3 days)
   - Implement core runtime
   - Build basic factory
   - Test with SecurityAgent

2. **Migrate Stage 2** (1-2 days)
   - Convert all 3 agents to configs
   - Verify tests pass
   - Benchmark performance

3. **Extend and polish** (2-3 days)
   - Add hot reload
   - Add templates
   - Add discovery API
   - Write documentation

4. **Open source** (ongoing)
   - Extract to separate lib
   - Publish as `synapse_orchestrator`
   - Share with Jido community
   - Become standard pattern

## Success Criteria

✅ **Baseline Met**: All Stage 2 functionality via pure configuration
✅ **10x Reduction**: New agents require 90% less code
✅ **Hot Reload**: Add/remove agents without restart
✅ **Self-Healing**: Crashed agents automatically respawn
✅ **Discovery**: Query running agents via API
✅ **Tests Pass**: All 177 tests still pass
✅ **Demo Works**: Stage2Demo.run() identical output

---

**This is the generalization layer that makes Jido truly orchestrable.**

Instead of writing agents, you **configure** them.
Instead of managing lifecycle, the system **maintains** it.
Instead of boilerplate, you have **pure business logic**.

**Puppet for Jido. Configuration as code. Declarative multi-agent systems.**
