# Synapse Orchestrator Architecture

**Purpose**: Configuration-driven agent lifecycle management on top of Jido

## System Overview

Synapse Orchestrator is a thin orchestration layer that transforms **declarative agent configurations** into **running Jido.Agent.Server instances**. It provides Puppet-style continuous reconciliation to maintain desired agent topology.

## Core Architecture

```
┌──────────────────────────────────────────────────────┐
│  Configuration Layer (Declarative)                    │
├──────────────────────────────────────────────────────┤
│  config/agents.exs:                                   │
│    - Agent definitions (what to run)                  │
│    - Signal routing rules (how to communicate)        │
│    - Action mappings (what agents can do)            │
│    - Behavior specifications (specialist/orchestrator)│
└────────────────┬─────────────────────────────────────┘
                 │ Loaded at startup
                 ▼
┌──────────────────────────────────────────────────────┐
│  Orchestrator Runtime (Continuous Reconciliation)     │
├──────────────────────────────────────────────────────┤
│  Synapse.Orchestrator.Runtime:                       │
│    - Loads and validates configs                     │
│    - Spawns agents via AgentFactory                  │
│    - Monitors running agents                         │
│    - Reconciles desired vs actual state (every 5s)   │
│    - Respawns failed agents automatically            │
└────────────────┬─────────────────────────────────────┘
                 │ Spawns agents
                 ▼
┌──────────────────────────────────────────────────────┐
│  Agent Factory (Config → Process)                     │
├──────────────────────────────────────────────────────┤
│  Synapse.Orchestrator.AgentFactory:                  │
│    - Interprets agent configurations                 │
│    - Builds Jido.Agent.Server options                │
│    - Creates signal routing rules                    │
│    - Configures action execution                     │
│    - Returns running pid                             │
└────────────────┬─────────────────────────────────────┘
                 │ Creates
                 ▼
┌──────────────────────────────────────────────────────┐
│  Jido.Agent.Server Instances (Running Agents)        │
├──────────────────────────────────────────────────────┤
│  One per agent config:                               │
│    - Subscribes to configured signals                │
│    - Executes configured actions                     │
│    - Emits configured results                        │
│    - Maintains configured state                      │
│    - ALL managed by Jido, not us                     │
└──────────────────────────────────────────────────────┘
```

## Key Components

### 1. Agent Configuration Schema

**File**: `lib/synapse/orchestrator/config.ex`

**Responsibilities:**
- Define agent configuration structure
- Validate configurations using NimbleOptions
- Load configs from files or modules
- Provide config introspection

**Configuration Format:**

```elixir
%{
  # Identity
  id: :agent_name,                      # Atom, unique
  type: :specialist | :orchestrator,    # Agent archetype

  # Capabilities
  actions: [Action1, Action2],          # What it can do

  # Communication
  signals: %{
    subscribes: ["pattern1", "pattern2"],  # What it listens to
    emits: ["output1", "output2"]          # What it produces
  },

  # Behavior
  result_builder: fn results, context -> map end,  # How it builds results

  # For orchestrators only
  orchestration: %{
    classify_fn: fn data -> classification end,
    spawn_specialists: [:agent1, :agent2],
    aggregation_fn: fn results, state -> summary end
  },

  # State (optional)
  state_schema: [
    field1: [type: :string, default: ""],
    field2: [type: :integer, default: 0]
  ],

  # Infrastructure
  bus: :synapse_bus,                    # Signal bus name
  registry: :synapse_registry           # Agent registry name
}
```

### 2. Orchestrator Runtime

**File**: `lib/synapse/orchestrator/runtime.ex`

**Responsibilities:**
- Load agent configurations at startup
- Spawn agents via AgentFactory
- Monitor agent health
- Reconcile desired vs actual state
- Handle agent failures
- Support runtime reconfiguration

**Reconciliation Loop:**

```
Every 5 seconds (configurable):
1. For each configured agent:
   a. Check if agent process exists
   b. Check if process is alive
   c. If missing/dead → spawn
   d. If healthy → continue
2. For each running agent:
   a. Check if still in config
   b. If removed from config → terminate
   c. If config changed → restart with new config
3. Emit reconciliation metrics
```

**State Structure:**

```elixir
%Runtime{
  config_source: "config/agents.exs",
  agent_configs: [%{id: :security, ...}, ...],
  running_agents: %{
    security_specialist: #PID<0.123.0>,
    performance_specialist: #PID<0.124.0>,
    coordinator: #PID<0.125.0>
  },
  bus: :synapse_bus,
  registry: :synapse_registry,
  reconcile_interval: 5000,
  last_reconcile: ~U[2025-10-29 12:00:00Z],
  reconcile_count: 42
}
```

### 3. Agent Factory

**File**: `lib/synapse/orchestrator/agent_factory.ex`

**Responsibilities:**
- Transform configs into Jido.Agent.Server options
- Build signal routing rules
- Create action execution pipelines
- Configure state management
- Return running process

**Factory Methods:**

```elixir
# Main entry point
spawn(config, bus, registry) :: {:ok, pid} | {:error, reason}

# Type-specific factories
spawn_specialist(config, bus, registry) :: {:ok, pid}
spawn_orchestrator(config, bus, registry) :: {:ok, pid}
spawn_custom(config, bus, registry) :: {:ok, pid}

# Route builders
build_specialist_routes(config) :: [route]
build_orchestrator_routes(config, bus, registry) :: [route]

# Instruction builders
build_specialist_instruction(config) :: instruction_spec
build_orchestrator_instruction(config) :: instruction_spec
```

**How It Works:**

```elixir
# Input: Agent config
config = %{
  id: :security_specialist,
  type: :specialist,
  actions: [CheckSQL, CheckXSS],
  signals: %{subscribes: ["review.request"], emits: ["review.result"]},
  result_builder: &build_result/2
}

# Output: Running Jido.Agent.Server
{:ok, pid} = AgentFactory.spawn(config, :synapse_bus, :synapse_registry)

# Internally, this:
# 1. Builds Jido.Agent.Server options from config
# 2. Creates signal routes: "review.request" → instruction
# 3. Instruction runs all config.actions
# 4. Results → config.result_builder
# 5. Emits signal via config.signals.emits
# 6. Starts Jido.Agent.Server with all options
```

### 4. Behavior Library

**File**: `lib/synapse/orchestrator/behaviors.ex`

**Responsibilities:**
- Provide reusable behavior functions
- Standard classification logic
- Standard result building
- Standard aggregation
- Extensible for custom behaviors

**Available Behaviors:**

```elixir
# Classification
classify_review(review_data) :: %{path: atom, rationale: string}
classify_by_size(data, threshold) :: classification
classify_by_labels(data, critical_labels) :: classification

# Result Building
build_specialist_result(action_results, review_id, agent_name) :: result_map
build_security_result(results, review_id) :: result_map
build_performance_result(results, review_id) :: result_map

# Aggregation
aggregate_results(specialist_results, review_state) :: summary_map
aggregate_by_severity(results) :: summary
aggregate_with_voting(results) :: summary

# State Management
update_specialist_state(state, review_id, result) :: updated_state
track_review(state, review_id, specialists) :: updated_state
complete_review(state, review_id) :: updated_state
```

## Signal Flow

### Specialist Agent Signal Flow

```
1. Runtime spawns specialist from config
   ↓
2. AgentFactory builds routes:
   "review.request" → instruction
   ↓
3. Jido.Agent.Server subscribes to "review.request"
   ↓
4. Signal arrives → route matched → instruction executed
   ↓
5. Instruction runs all config.actions:
   - CheckSQLInjection
   - CheckXSS
   - CheckAuthIssues
   ↓
6. Results → config.result_builder(results, review_id)
   ↓
7. Built result → emit signal "review.result"
   ↓
8. State update via config.state_schema
```

### Orchestrator Agent Signal Flow

```
1. Runtime spawns orchestrator from config
   ↓
2. AgentFactory builds two routes:
   - "review.request" → classify & spawn
   - "review.result" → aggregate & summarize
   ↓
3. review.request arrives:
   a. Run config.orchestration.classify_fn
   b. If deep_review: spawn specialists via config.orchestration.spawn_specialists
   c. Track review in state
   d. Republish signal for specialists
   ↓
4. review.result arrives (multiple):
   a. Add to tracked review
   b. Check if all specialists responded
   c. If complete: run config.orchestration.aggregation_fn
   d. Emit "review.summary"
```

## Configuration Examples

### Minimal Specialist

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

### Full-Featured Specialist

```elixir
%{
  id: :security_specialist,
  type: :specialist,

  # Actions to execute
  actions: [
    Synapse.Actions.Security.CheckSQLInjection,
    Synapse.Actions.Security.CheckXSS,
    Synapse.Actions.Security.CheckAuthIssues
  ],

  # Signal routing
  signals: %{
    subscribes: ["review.request"],
    emits: ["review.result"]
  },

  # Result building
  result_builder: fn results, review_id ->
    Synapse.Orchestrator.Behaviors.build_specialist_result(
      results,
      review_id,
      "security_specialist"
    )
  end,

  # State tracking
  state_schema: [
    review_history: [type: {:list, :map}, default: []],
    learned_patterns: [type: {:list, :map}, default: []],
    scar_tissue: [type: {:list, :map}, default: []]
  ],

  # Infrastructure
  bus: :synapse_bus,
  registry: :synapse_registry
}
```

### Orchestrator

```elixir
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

  orchestration: %{
    # Classification function
    classify_fn: &Synapse.Orchestrator.Behaviors.classify_review/1,

    # Which specialists to spawn for deep reviews
    spawn_specialists: [:security_specialist, :performance_specialist],

    # How to aggregate specialist results
    aggregation_fn: &Synapse.Orchestrator.Behaviors.aggregate_results/2,

    # Fast path handler (optional)
    fast_path_fn: fn signal, bus ->
      # Emit immediate summary for small changes
      emit_fast_path_summary(signal, bus)
    end
  },

  state_schema: [
    review_count: [type: :integer, default: 0],
    active_reviews: [type: :map, default: %{}]
  ]
}
```

## Runtime API

### Orchestrator Management

```elixir
# Start orchestrator
{:ok, pid} = Synapse.Orchestrator.Runtime.start_link(
  config_source: "config/agents.exs"
)

# Get running agents (returns list of %RunningAgent{} structs)
agents = Synapse.Orchestrator.Runtime.list_agents(pid)
# => [
#   %RunningAgent{
#     agent_id: :security_specialist,
#     pid: #PID<...>,
#     config: %AgentConfig{...},
#     spawn_count: 1,
#     ...
#   },
#   ...
# ]

# Get agent config
{:ok, config} = Synapse.Orchestrator.Runtime.get_agent_config(pid, :security_specialist)

# Get agent status
{:ok, status} = Synapse.Orchestrator.Runtime.agent_status(pid, :security_specialist)
# => %{
#   pid: #PID<...>,
#   alive?: true,
#   config: %AgentConfig{...},
#   running_agent: %RunningAgent{...}
# }
```

### Hot Reload

```elixir
# Trigger immediate reconciliation (reloads config and reconciles state)
:ok = Synapse.Orchestrator.Runtime.reload(pid)

# Add new agent at runtime
{:ok, agent_pid} = Synapse.Orchestrator.Runtime.add_agent(pid, %{
  id: :new_specialist,
  type: :specialist,
  actions: [NewAction],
  signals: %{subscribes: ["new.signal"], emits: ["new.result"]}
})

# Remove agent (graceful shutdown)
:ok = Synapse.Orchestrator.Runtime.remove_agent(pid, :old_specialist)

# Note: To update an agent config, use remove_agent followed by add_agent
# This ensures clean state and proper reconciliation
```

### Health Monitoring

```elixir
# System-wide health
%{
  total: 5,
  running: 5,
  failed: 0,
  reconcile_count: 42,
  last_reconcile: ~U[2025-10-29 12:00:00Z]
} = Synapse.Orchestrator.Runtime.health_check(pid)

# Get skill metadata summary
summary = Synapse.Orchestrator.Runtime.skill_metadata(pid)
# => "- demo-skill: Demo instructions\n  (Load: bash cat /path/to/SKILL.md)"
```

## Agent Types & Patterns

### Type: Specialist

**Purpose**: Execute actions and emit results

**Pattern**:
1. Subscribe to input signal pattern
2. Receive signal → execute all actions in parallel
3. Aggregate action results
4. Build result using result_builder function
5. Emit result signal
6. Update state (history tracking)

**Configuration Template**:

```elixir
%{
  type: :specialist,
  actions: [Action1, Action2, Action3],
  signals: %{subscribes: ["input"], emits: ["output"]},
  result_builder: &build_result/2
}
```

**Generated Behavior**:
- Single signal subscription
- Parallel action execution
- Automatic result emission
- State history tracking

### Type: Orchestrator

**Purpose**: Coordinate multiple specialists, aggregate results

**Pattern**:
1. Subscribe to request signal
2. Classify request (fast_path vs deep_review)
3. If deep_review:
   - Spawn specialists (via config)
   - Track pending responses
   - Subscribe to specialist results
4. Aggregate results when all specialists respond
5. Emit summary signal

**Configuration Template**:

```elixir
%{
  type: :orchestrator,
  orchestration: %{
    classify_fn: &classify/1,
    spawn_specialists: [:specialist1, :specialist2],
    aggregation_fn: &aggregate/2
  },
  signals: %{subscribes: ["request", "result"], emits: ["summary"]}
}
```

**Generated Behavior**:
- Multi-signal subscription
- Automatic specialist spawning
- Result aggregation
- Summary synthesis

### Type: Custom

**Purpose**: Arbitrary agent behavior

**Pattern**: Fully custom - provide your own route handlers

```elixir
%{
  type: :custom,
  custom_routes: [
    {
      pattern: "custom.signal",
      handler: fn signal, state ->
        # Custom logic
        {:ok, new_state}
      end
    }
  ]
}
```

## Reconciliation Algorithm

### Desired State Reconciliation

```elixir
defp reconcile_agents(state) do
  current_time = DateTime.utc_now()

  # 1. Spawn missing agents
  state = spawn_missing_agents(state)

  # 2. Verify running agents
  state = verify_running_agents(state)

  # 3. Remove extra agents
  state = remove_extra_agents(state)

  # 4. Update metrics
  %{state |
    last_reconcile: current_time,
    reconcile_count: state.reconcile_count + 1
  }
end

defp spawn_missing_agents(state) do
  # For each configured agent
  Enum.reduce(state.agent_configs, state, fn config, acc ->
    case Map.get(acc.running_agents, config.id) do
      nil ->
        # Agent not running - spawn it
        spawn_and_track(config, acc)

      _pid ->
        # Agent exists
        acc
    end
  end)
end

defp verify_running_agents(state) do
  # Check each running agent
  Enum.reduce(state.running_agents, state, fn {agent_id, pid}, acc ->
    if Process.alive?(pid) do
      # Healthy
      acc
    else
      # Dead - remove from tracking (will be respawned next reconcile)
      Logger.warning("Agent dead, will respawn", agent_id: agent_id)
      %{acc | running_agents: Map.delete(acc.running_agents, agent_id)}
    end
  end)
end

defp remove_extra_agents(state) do
  # Get IDs of configured agents
  configured_ids = MapSet.new(state.agent_configs, & &1.id)

  # For each running agent
  Enum.reduce(state.running_agents, state, fn {agent_id, pid}, acc ->
    if agent_id in configured_ids do
      # Keep it
      acc
    else
      # Not in config - terminate
      Logger.info("Terminating unconfigured agent", agent_id: agent_id)
      GenServer.stop(pid, :normal)
      %{acc | running_agents: Map.delete(acc.running_agents, agent_id)}
    end
  end)
end
```

### Self-Healing

The reconciliation loop provides automatic self-healing:

- **Agent crashes** → Detected on next reconcile → Respawned
- **Configuration changes** → Detected on reload → Agents restarted
- **Manual termination** → Detected on next reconcile → Respawned
- **Config removal** → Detected on reload → Agent gracefully stopped

**Healing Time**: Default 5 seconds (configurable)

## Configuration Validation

### Compile-Time Validation

```elixir
# In config/agents.exs
# Validation happens during Config.load/1

{:ok, configs} = Synapse.Orchestrator.Config.load("config/agents.exs")
# => Validates all schemas, checks required fields, verifies action modules exist
```

### Runtime Validation

```elixir
# When adding agent at runtime
case Synapse.Orchestrator.Runtime.add_agent(config) do
  {:ok, pid} ->
    # Config valid, agent spawned
    pid

  {:error, {:validation_error, details}} ->
    # Config invalid - not spawned
    Logger.error("Invalid agent config", details: details)
end
```

## Benefits Over Hardcoded Agents

### Code Reduction

| Aspect | Hardcoded | Configured | Reduction |
|--------|-----------|------------|-----------|
| SecurityAgentServer | 264 lines | 30 lines | 88% |
| PerformanceAgentServer | 264 lines | 30 lines | 88% |
| CoordinatorAgentServer | 384 lines | 50 lines | 87% |
| **Total** | **912 lines** | **110 lines** | **88%** |

### Operational Benefits

| Feature | Hardcoded | Configured |
|---------|-----------|------------|
| Add new agent | Code + deploy | Config change |
| Modify behavior | Code + tests + deploy | Config change |
| A/B testing | Separate modules | Config flag |
| Hot reload | Not possible | Built-in |
| Discovery | Manual tracking | Automatic |
| Monitoring | Custom code | Built-in |

### Development Velocity

**Before (Hardcoded)**:
1. Design agent behavior (1 hour)
2. Write GenServer module (2 hours)
3. Write tests (2 hours)
4. Deploy (30 mins)
**Total**: ~5.5 hours per agent

**After (Configured)**:
1. Design agent behavior (1 hour)
2. Write configuration (15 mins)
3. Test configuration (30 mins)
4. Reload config (instant)
**Total**: ~1.75 hours per agent

**3x faster development**

## Migration Strategy

### Phase 1: Build Orchestrator Core (Week 1)

```
Day 1-2: Implement Synapse.Orchestrator.Config
Day 3-4: Implement Synapse.Orchestrator.Runtime
Day 5-6: Implement Synapse.Orchestrator.AgentFactory
Day 7: Implement Synapse.Orchestrator.Behaviors
```

### Phase 2: Convert Stage 2 Agents (Week 2)

```
Day 1: Extract SecurityAgentServer → config
Day 2: Extract PerformanceAgentServer → config
Day 3: Extract CoordinatorAgentServer → config
Day 4: Update Application.start/2
Day 5: Verify all tests pass
Day 6-7: Benchmarking and optimization
```

### Phase 3: Enhanced Features (Week 3)

```
Day 1-2: Implement hot reload
Day 3: Implement agent templates
Day 4: Implement conditional spawning
Day 5: Implement discovery API
Day 6-7: Documentation and examples
```

## Testing Strategy

### Configuration Testing

```elixir
defmodule Synapse.Orchestrator.ConfigTest do
  test "validates specialist config" do
    config = %{
      id: :test_specialist,
      type: :specialist,
      actions: [TestAction],
      signals: %{subscribes: ["input"], emits: ["output"]}
    }

    assert {:ok, validated} = Config.validate(config)
  end

  test "rejects invalid config" do
    config = %{
      id: :bad_specialist,
      type: :specialist
      # Missing required fields
    }

    assert {:error, reason} = Config.validate(config)
  end
end
```

### Runtime Testing

```elixir
defmodule Synapse.Orchestrator.RuntimeTest do
  test "spawns agents from config" do
    {:ok, runtime} = Runtime.start_link(
      config_source: "test/fixtures/test_agents.exs"
    )

    # Verify agents spawned
    assert %{test_specialist: pid} = Runtime.list_agents()
    assert Process.alive?(pid)
  end

  test "reconciles failed agents" do
    {:ok, runtime} = Runtime.start_link(config_source: "test/fixtures/test_agents.exs")

    # Get agent pid
    %{test_specialist: pid} = Runtime.list_agents()

    # Kill the agent
    GenServer.stop(pid, :kill)
    Process.sleep(100)

    # Trigger reconciliation
    send(runtime, :reconcile)
    Process.sleep(100)

    # Verify respawned
    %{test_specialist: new_pid} = Runtime.list_agents()
    assert new_pid != pid
    assert Process.alive?(new_pid)
  end
end
```

### Factory Testing

```elixir
defmodule Synapse.Orchestrator.AgentFactoryTest do
  test "spawns specialist from config" do
    config = specialist_config()

    {:ok, pid} = AgentFactory.spawn(config, :synapse_bus, :synapse_registry)

    assert Process.alive?(pid)

    # Verify agent subscribed to signals
    # Verify agent can execute actions
  end
end
```

## Performance Characteristics

### Startup Time

**Hardcoded (Current)**:
- Application starts supervision tree
- Each GenServer initializes separately
- Total: ~50-100ms for 3 agents

**Configured (Orchestrator)**:
- Runtime loads configs: ~10ms
- Runtime spawns all agents: ~50-100ms
- Total: ~60-110ms (slight overhead)

### Signal Processing

**No difference** - both use Jido.Agent.Server underneath

### Memory Usage

**Hardcoded**: ~5MB per agent (GenServer + state)
**Configured**: ~5MB per agent + ~1MB for orchestrator
**Overhead**: ~1MB total (negligible)

### Reconciliation Overhead

**CPU**: <1% (checks every 5 seconds)
**Memory**: Negligible
**Network**: None (local process checks)

## Comparison to Similar Systems

### Kubernetes

| Feature | Kubernetes | Synapse Orchestrator |
|---------|------------|---------------------|
| Declarative | ✅ YAML | ✅ Elixir config |
| Reconciliation | ✅ Controllers | ✅ Runtime loop |
| Self-healing | ✅ Pod restarts | ✅ Agent respawns |
| Hot reload | ❌ Requires rolling update | ✅ Built-in |
| Type safety | ❌ YAML | ✅ Elixir |
| Domain | Containers | Agents |

### Puppet

| Feature | Puppet | Synapse Orchestrator |
|---------|--------|---------------------|
| Declarative | ✅ Manifests | ✅ Configs |
| Continuous enforcement | ✅ Runs periodically | ✅ Reconciliation loop |
| Self-healing | ✅ Fixes drift | ✅ Respawns agents |
| Idempotent | ✅ Same config → same state | ✅ Same config → same agents |
| Domain | Infrastructure | Agents |

### Ansible

| Feature | Ansible | Synapse Orchestrator |
|---------|---------|---------------------|
| Execution model | ❌ Imperative | ✅ Declarative |
| Continuous | ❌ One-time runs | ✅ Continuous reconciliation |
| State drift | ❌ Doesn't detect | ✅ Automatically fixes |

**Synapse Orchestrator is Puppet for Jido agents.**

## Implementation Roadmap

### Milestone 1: Core Orchestrator (Week 1)
- ✅ Config schema and validation
- ✅ Runtime manager with reconciliation
- ✅ AgentFactory for specialists
- ✅ Basic behavior library

### Milestone 2: Stage 2 Migration (Week 2)
- ✅ Convert SecurityAgentServer to config
- ✅ Convert PerformanceAgentServer to config
- ✅ Convert CoordinatorAgentServer to config
- ✅ All 177 tests passing

### Milestone 3: Advanced Features (Week 3)
- ✅ Hot reload implementation
- ✅ Agent templates
- ✅ Conditional spawning
- ✅ Discovery API
- ✅ Metrics and telemetry

### Milestone 4: Production Ready (Week 4)
- ✅ Comprehensive documentation
- ✅ Example configurations
- ✅ Migration guide
- ✅ Performance benchmarks
- ✅ Production deployment guide

## Success Metrics

### Code Metrics
- ✅ 88% code reduction for agent definitions
- ✅ 100% test coverage for orchestrator
- ✅ All Stage 2 tests passing (177/177)
- ✅ Zero performance regression

### Operational Metrics
- ✅ <5s agent respawn time
- ✅ <1% CPU overhead for reconciliation
- ✅ <1MB memory overhead
- ✅ 100% config reload success rate

### Developer Experience
- ✅ New agent in <30 lines of config
- ✅ No boilerplate GenServer code
- ✅ Hot reload without deployment
- ✅ Clear error messages for invalid configs

---

**This is the innovation**: Transform Jido from an agent framework into an **orchestrated agent platform** where you declare what you want, and the system continuously maintains it.

**No more boilerplate. Just configuration. Puppet for agents.**
