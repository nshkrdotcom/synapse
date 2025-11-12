# Stage 2 – Multi-Agent Orchestration

## Status: ✅ COMPLETE

Stage 2 delivers **full multi-agent orchestration** where CoordinatorAgent autonomously spawns and manages specialist agents via the signal bus.

## What's Delivered

### New Components

1. **PerformanceAgentServer** (`lib/synapse/agents/performance_agent_server.ex`)
   - GenServer wrapper for PerformanceAgent
   - Subscribes to `review.request` signals
   - Runs CheckComplexity, CheckMemoryUsage, ProfileHotPath actions
   - Emits `review.result` signals with performance findings

2. **CoordinatorAgentServer** (`lib/synapse/agents/coordinator_agent_server.ex`)
   - Orchestration hub for multi-agent reviews
   - Subscribes to both `review.request` and `review.result` signals
   - Classifies changes (fast_path vs deep_review)
   - Spawns SecurityAgentServer and PerformanceAgentServer for deep reviews
   - Aggregates results from all specialists
   - Emits `review.summary` signals

3. **Enhanced AgentRegistry** (`lib/synapse/agent_registry.ex`)
   - Updated to support spawning GenServer agents
   - Automatically detects if module implements `start_link/1`
   - Maintains backward compatibility with stateless agents

### Signal Flow

```
review.request
  ↓
CoordinatorAgentServer
  ├─> Classify (ClassifyChange action)
  ├─> If deep_review:
  │   ├─> Spawn SecurityAgentServer (via AgentRegistry)
  │   ├─> Spawn PerformanceAgentServer (via AgentRegistry)
  │   └─> Republish review.request for specialists
  ↓
Specialists process review
  ├─> SecurityAgentServer → review.result
  └─> PerformanceAgentServer → review.result
  ↓
CoordinatorAgentServer aggregates results
  ↓
review.summary (final output)
```

## Quick Start

```elixir
# Run the demo
iex -S mix
iex> Synapse.Examples.Stage2Demo.run()

# Check system health
iex> Synapse.Examples.Stage2Demo.health_check()
%{
  bus: :healthy,
  coordinator: :healthy,
  security_specialist: :healthy,
  performance_specialist: :healthy
}
```

## Test Coverage

- **177 tests passing** (161 + 5 + 8 + 3)
  - 5 PerformanceAgentServer tests
  - 8 CoordinatorAgentServer tests
  - 3 Stage 2 integration tests
- **0 failures**
- Full end-to-end orchestration verified

## Key Features

### 1. Autonomous Specialist Spawning

Coordinator automatically spawns specialists based on classification:

```elixir
# Deep review → spawns both specialists
classification.path == :deep_review
# Fast path → no specialists, immediate summary
classification.path == :fast_path
```

### 2. Result Aggregation

Coordinator tracks pending specialists and aggregates their results:

```elixir
active_reviews: %{
  review_id => %{
    status: :awaiting | :ready,
    pending_specialists: ["security_specialist", "performance_specialist"],
    results: [specialist_result1, specialist_result2],
    ...
  }
}
```

### 3. Multi-Signal Subscription

Coordinator listens to two signal types simultaneously:
- `review.request` - Incoming review requests
- `review.result` - Specialist results to aggregate

## Architecture Patterns

### GenServer Agent Pattern

All agents follow this structure:

```elixir
defmodule AgentServer do
  use GenServer

  # State: %{agent: stateless_agent, bus: atom, subscription_id: string}

  def init(opts) do
    agent = Agent.new(opts[:id])
    {:ok, sub_id} = subscribe_to_signals(bus)
    {:ok, %{agent: agent, bus: bus, subscription_id: sub_id}}
  end

  def handle_info({:signal, signal}, state) do
    # Process signal, run actions, emit results
    {:noreply, updated_state}
  end

  def terminate(_reason, state) do
    unsubscribe_from_bus(state)
    :ok
  end
end
```

### Idempotent Spawning

AgentRegistry ensures only one instance of each specialist:

```elixir
{:ok, pid} = AgentRegistry.get_or_spawn(
  :synapse_registry,
  "security_specialist",
  SecurityAgentServer,
  bus: :synapse_bus
)
```

## Files Added/Modified

### New Files
- `lib/synapse/agents/performance_agent_server.ex` (264 lines)
- `lib/synapse/agents/coordinator_agent_server.ex` (384 lines)
- `lib/synapse/examples/stage_2_demo.ex` (263 lines)
- `test/synapse/agents/performance_agent_server_test.exs` (268 lines)
- `test/synapse/agents/coordinator_agent_server_test.exs` (330 lines)
- `test/synapse/integration/stage_2_orchestration_test.exs` (270 lines)

### Modified Files
- `lib/synapse/agent_registry.ex` - Added GenServer support
- `lib/synapse/actions/review/generate_summary.ex` - Fixed fast_path handling

**Total**: ~1,800 lines of new code + tests + docs

## Next Steps (Stage 3)

- Scar tissue learning from failures
- Directive.Enqueue for work distribution
- Timeout handling for unresponsive specialists
- Dynamic specialist registration
- Metrics and telemetry

## See Also

- [Stage 0 README](../stage_0/README.md) - Foundation
- [Stage 1 Architecture](../stage_1/architecture.md) - Design
- [Stage 1 Signals](../stage_1/signals.md) - Signal contracts
- [ARCHITECTURE.md](../../ARCHITECTURE.md) - System overview
