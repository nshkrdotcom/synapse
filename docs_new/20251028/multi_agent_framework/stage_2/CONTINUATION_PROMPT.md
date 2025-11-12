# Stage 2 Continuation Prompt

## Context

You are continuing the Synapse Multi-Agent Framework implementation. **Stage 0 and Stage 1 are complete and fully tested.** Stage 2 builds on this foundation to create a **full multi-agent orchestration system** where CoordinatorAgent spawns and manages specialist agents via directives.

## What Exists (Stage 0 + Stage 1)

### Working Components

1. **Signal.Bus** - Running in supervision tree at `:synapse_bus`
2. **SecurityAgentServer** - GenServer that autonomously processes review requests
3. **AgentRegistry** - Process registry (ready for multi-agent spawning)
4. **8 Actions** - All tested and working:
   - Review: ClassifyChange, GenerateSummary
   - Security: CheckSQLInjection, CheckXSS, CheckAuthIssues
   - Performance: CheckComplexity, CheckMemoryUsage, ProfileHotPath
5. **3 Agent Structs** - Stateless agents with state management:
   - CoordinatorAgent (orchestration logic)
   - SecurityAgent (security specialist)
   - PerformanceAgent (performance specialist)

### What's Proven

- ✅ Signal-based communication works
- ✅ GenServer agents can subscribe and process signals
- ✅ Actions execute and return structured results
- ✅ State management (learned_patterns, scar_tissue, history) works
- ✅ 161 tests passing, 0 failures
- ✅ Demo proves end-to-end autonomy: `Synapse.Examples.Stage0Demo.run()`

## Required Reading

### Documentation (READ IN ORDER)

1. **[Stage 0 README](stage_0/README.md)** - What foundation was built
2. **[Stage 1 Architecture](stage_1/architecture.md)** - The DESIGN we're implementing
3. **[Stage 1 Agents](stage_1/agents.md)** - Agent specifications
4. **[Stage 1 Signals](stage_1/signals.md)** - Signal contracts (CRITICAL)
5. **[Stage 1 Testing](stage_1/testing.md)** - Test strategy to follow
6. **[ARCHITECTURE.md](../ARCHITECTURE.md)** - Current running system
7. **[IMPLEMENTATION_SUMMARY.md](../IMPLEMENTATION_SUMMARY.md)** - What's done

### Source Code (UNDERSTAND THESE PATTERNS)

**Working Examples**:
```
lib/synapse/agents/security_agent_server.ex   ← GenServer pattern to replicate
lib/synapse/agents/security_agent.ex          ← Stateless agent pattern
lib/synapse/agents/coordinator_agent.ex       ← Logic to wrap in GenServer
lib/synapse/examples/stage_0_demo.ex          ← How signal flow works
```

**Test Examples**:
```
test/synapse/agents/security_agent_server_test.exs   ← GenServer testing pattern
test/synapse/agents/security_agent_test.exs          ← State management tests
test/synapse/integration/review_signal_flow_test.exs ← Integration test pattern
test/support/signal_bus_helpers.ex                   ← Test utilities
```

**Jido Documentation** (from previous prompt context):
```
agentjido/jido/guides/agents/stateful.md       ← Jido.Agent.Server usage
agentjido/jido_signal/guides/event-bus.md      ← Signal.Bus patterns
```

## Stage 2 Goals

### Objective

Build **full multi-agent orchestration** where CoordinatorAgent autonomously:
1. Receives `review.request` signals
2. Classifies changes (fast_path vs deep_review)
3. **Spawns specialists** via `Directive.Spawn` (if not running)
4. **Distributes work** via `Directive.Enqueue`
5. **Aggregates results** from both specialists
6. Emits `review.summary` signal

### Success Criteria

✅ **End-to-end signal flow working**:
```
review.request
  ↓
CoordinatorAgentServer
  ├─> Directive.Spawn → SecurityAgentServer
  ├─> Directive.Spawn → PerformanceAgentServer
  ├─> Both specialists process signals
  ├─> Both emit review.result
  └─> Coordinator aggregates and emits review.summary
```

✅ **Observable in iex**:
```elixir
iex> Stage2Demo.run()
[info] CoordinatorAgent received review.request
[info] Spawning SecurityAgent
[info] Spawning PerformanceAgent
[info] SecurityAgent processing review
[info] PerformanceAgent processing review
[info] SecurityAgent emitted result
[info] PerformanceAgent emitted result
[info] CoordinatorAgent synthesizing results
[info] CoordinatorAgent emitted review.summary

✓ Full orchestration complete!
```

✅ **All tests passing**: Expect ~190 total tests (161 existing + ~30 new)

✅ **No warnings**: `mix precommit` clean

## Stage 2 Scope (TDD Order)

### 1. PerformanceAgentServer GenServer

**Pattern**: Mirror `SecurityAgentServer` exactly.

**Test First**:
- [ ] **Test**: PerformanceAgentServer.start_link starts process
- [ ] **Test**: Subscribes to "review.request" on init
- [ ] **Test**: Processes signal and runs performance checks
- [ ] **Test**: Emits "review.result" with performance findings
- [ ] **Test**: Maintains PerformanceAgent state

**Implementation**:
- [ ] Create `lib/synapse/agents/performance_agent_server.ex`
- [ ] Copy SecurityAgentServer structure
- [ ] Replace security actions with performance actions
- [ ] Run tests until green

**Files**:
- New: `lib/synapse/agents/performance_agent_server.ex`
- New: `test/synapse/agents/performance_agent_server_test.exs`

### 2. CoordinatorAgentServer GenServer

**Pattern**: More complex - handles spawning and aggregation.

**Test First**:
- [ ] **Test**: CoordinatorAgentServer.start_link starts process
- [ ] **Test**: Subscribes to "review.request" on init
- [ ] **Test**: Receives signal and classifies change
- [ ] **Test**: Returns Directive.Spawn for specialists
- [ ] **Test**: Subscribes to "review.result" pattern
- [ ] **Test**: Aggregates results from both specialists
- [ ] **Test**: Emits "review.summary" when both complete
- [ ] **Test**: Handles missing specialist responses (timeout)

**Implementation**:
- [ ] Create `lib/synapse/agents/coordinator_agent_server.ex`
- [ ] Implement init with "review.request" subscription
- [ ] Implement classification in handle_info
- [ ] Implement directive emission (for spawning)
- [ ] Implement "review.result" subscription
- [ ] Implement result aggregation
- [ ] Implement summary emission
- [ ] Run tests until green

**Files**:
- New: `lib/synapse/agents/coordinator_agent_server.ex`
- New: `test/synapse/agents/coordinator_agent_server_test.exs`

### 3. Directive Processing Infrastructure

**Currently**: Directives work with stateless agents only.

**Need**: GenServer agents to process directives.

**Test First**:
- [ ] **Test**: CoordinatorAgent returns Directive.Spawn in result
- [ ] **Test**: Server extracts directives from action results
- [ ] **Test**: Server processes Directive.Spawn by calling AgentRegistry
- [ ] **Test**: Server processes Directive.Enqueue (future)
- [ ] **Test**: Spawned agents are tracked

**Implementation**:
- [ ] Add directive extraction to coordinator handle_info
- [ ] Implement process_directives/2 function
- [ ] Wire AgentRegistry.get_or_spawn for Directive.Spawn
- [ ] Handle errors in spawning
- [ ] Run tests until green

**Files**:
- Modify: `lib/synapse/agents/coordinator_agent_server.ex`
- New: Tests in coordinator_agent_server_test.exs

### 4. Multi-Agent Result Aggregation

**Test First**:
- [ ] **Test**: Coordinator tracks review in active_reviews
- [ ] **Test**: Coordinator receives review.result from SecurityAgent
- [ ] **Test**: Coordinator receives review.result from PerformanceAgent
- [ ] **Test**: Coordinator knows when all specialists responded
- [ ] **Test**: Coordinator synthesizes results into summary
- [ ] **Test**: Summary includes findings from both specialists

**Implementation**:
- [ ] Subscribe to "review.result" in coordinator init
- [ ] Implement handle_info for review.result signals
- [ ] Track specialists in active_reviews
- [ ] Detect completion (all responded)
- [ ] Call synthesize_results when ready
- [ ] Emit review.summary signal

**Files**:
- Modify: `lib/synapse/agents/coordinator_agent_server.ex`
- Modify: `test/synapse/agents/coordinator_agent_server_test.exs`

### 5. End-to-End Integration Test

**Test First**:
- [ ] **Test**: Publish review.request to bus
- [ ] **Test**: Coordinator receives and spawns specialists
- [ ] **Test**: SecurityAgent processes and emits result
- [ ] **Test**: PerformanceAgent processes and emits result
- [ ] **Test**: Coordinator receives both results
- [ ] **Test**: Coordinator emits review.summary
- [ ] **Test**: Summary contains findings from both specialists
- [ ] **Test**: Full flow completes within 5 seconds
- [ ] **Test**: Agents clean up properly

**Implementation**:
- [ ] Create integration test in `test/synapse/integration/full_orchestration_test.exs`
- [ ] Start all components (bus, coordinator, specialists)
- [ ] Publish signal and track flow
- [ ] Assert all signals emitted
- [ ] Verify summary correctness
- [ ] Run until green

**Files**:
- New: `test/synapse/integration/full_orchestration_test.exs`

### 6. Stage 2 Demo

**Test First**:
- [ ] **Test**: Stage2Demo.run() completes successfully
- [ ] **Test**: Demo shows coordinator spawning specialists
- [ ] **Test**: Demo shows multi-agent interaction
- [ ] **Test**: Demo output is readable

**Implementation**:
- [ ] Create `lib/synapse/examples/stage_2_demo.ex`
- [ ] Implement run/0 for full orchestration
- [ ] Add health_check for all components
- [ ] Add detailed logging
- [ ] Run until working

**Files**:
- New: `lib/synapse/examples/stage_2_demo.ex`

### 7. Documentation Updates

- [ ] Update README.md with Stage 2 status
- [ ] Create stage_2/README.md
- [ ] Create stage_2/GETTING_STARTED.md
- [ ] Update ARCHITECTURE.md with new signal flows
- [ ] Update API_REFERENCE.md with new APIs
- [ ] Update IMPLEMENTATION_SUMMARY.md

## TDD Workflow

**For EVERY feature above**:

1. **Write failing test first**
   ```bash
   # Test should fail initially
   mix test test/path/to/test.exs
   # Expected: N tests, 1+ failures
   ```

2. **Implement minimum code to pass**
   ```elixir
   # Add implementation
   # Run test
   mix test test/path/to/test.exs
   # Expected: N tests, 0 failures
   ```

3. **Verify no regressions**
   ```bash
   mix test
   # Expected: All tests passing
   ```

4. **Clean up and document**
   ```bash
   mix format
   # Add @doc and examples
   # Update relevant docs
   ```

5. **Quality gate**
   ```bash
   mix precommit
   # Expected: All passing, no warnings
   ```

## Implementation Order (STRICT)

1. **PerformanceAgentServer** (easiest - copy SecurityAgentServer)
2. **CoordinatorAgentServer** (complex - orchestration)
3. **Directive Processing** (enable spawning)
4. **Result Aggregation** (coordinator collects results)
5. **Integration Test** (full flow)
6. **Demo** (observable example)
7. **Documentation** (guides and updates)

## Key Patterns to Follow

### GenServer Agent Pattern (from SecurityAgentServer)

```elixir
defmodule YourAgentServer do
  use GenServer
  require Logger

  # State: %{agent: stateless_agent_struct, bus: atom, subscription_id: string}

  def init(opts) do
    agent = YourAgent.new(opts[:id])
    {:ok, sub_id} = Jido.Signal.Bus.subscribe(bus, pattern, ...)
    {:ok, %{agent: agent, bus: bus, subscription_id: sub_id}}
  end

  def handle_info({:signal, signal}, state) do
    # Process signal
    # Run actions via Jido.Exec.run
    # Emit result signal
    # Update agent state
    {:noreply, %{state | agent: updated_agent}}
  end

  def terminate(_reason, state) do
    Jido.Signal.Bus.unsubscribe(state.bus, state.subscription_id)
    :ok
  end
end
```

### Directive Processing Pattern (NEW for Stage 2)

```elixir
defmodule CoordinatorAgentServer do
  def handle_info({:signal, %{type: "review.request"} = signal}, state) do
    # 1. Classify
    {:ok, classification} = CoordinatorAgent.classify_change(state.agent, ...)

    # 2. Decide what to do
    directives = case classification.path do
      :deep_review ->
        # Spawn specialists
        [
          %Jido.Agent.Directive.Spawn{
            module: SecurityAgentServer,
            args: [id: "security_specialist", bus: state.bus]
          },
          %Jido.Agent.Directive.Spawn{
            module: PerformanceAgentServer,
            args: [id: "performance_specialist", bus: state.bus]
          }
        ]
      :fast_path -> []
    end

    # 3. Process directives
    {:ok, updated_state} = process_directives(directives, state)

    # 4. Track review
    {:ok, updated_agent} = CoordinatorAgent.start_review(...)

    {:noreply, %{updated_state | agent: updated_agent}}
  end

  defp process_directives(directives, state) do
    Enum.reduce_while(directives, {:ok, state}, fn directive, {:ok, acc_state} ->
      case process_directive(directive, acc_state) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp process_directive(%Jido.Agent.Directive.Spawn{} = directive, state) do
    # Use AgentRegistry to spawn
    {:ok, _pid} = Synapse.AgentRegistry.get_or_spawn(
      :synapse_registry,
      directive.args[:id],
      directive.module,
      directive.args
    )
    {:ok, state}
  end
end
```

### Result Aggregation Pattern (NEW for Stage 2)

```elixir
def handle_info({:signal, %{type: "review.result"} = signal}, state) do
  review_id = signal.data.review_id

  # Add result to active review
  {:ok, updated_agent, ready?} = CoordinatorAgent.add_specialist_result(
    state.agent,
    review_id,
    signal.data
  )

  if ready? do
    # All specialists responded - synthesize
    review_state = updated_agent.state.active_reviews[review_id]

    {:ok, summary} = CoordinatorAgent.synthesize_results(
      updated_agent,
      review_id,
      review_state.results,
      classification_path,
      duration_ms
    )

    # Emit summary signal
    emit_summary_signal(summary, state.bus)

    # Clean up
    {:ok, final_agent} = CoordinatorAgent.complete_review(updated_agent, review_id)
    {:noreply, %{state | agent: final_agent}}
  else
    # Still waiting for more results
    {:noreply, %{state | agent: updated_agent}}
  end
end
```

## Critical Implementation Details

### Signal Subscriptions

**Coordinator needs TWO subscriptions**:
```elixir
def init(opts) do
  # 1. Subscribe to incoming requests
  {:ok, request_sub} = Jido.Signal.Bus.subscribe(
    bus, "review.request", ...
  )

  # 2. Subscribe to specialist results
  {:ok, result_sub} = Jido.Signal.Bus.subscribe(
    bus, "review.result", ...
  )

  state = %{
    agent: coordinator_agent,
    bus: bus,
    request_subscription: request_sub,
    result_subscription: result_sub
  }
end
```

### AgentRegistry Integration

**Update AgentRegistry to spawn GenServers** (not dummy processes):

```elixir
# In AgentRegistry
defp spawn_agent(agent_module, agent_id, opts) do
  # Instead of stateless agent + holder process:
  # Start actual GenServer if module implements start_link
  if function_exported?(agent_module, :start_link, 1) do
    # It's a GenServer module (e.g., SecurityAgentServer)
    agent_module.start_link(Keyword.put(opts, :id, agent_id))
  else
    # It's a stateless agent module (fallback to old behavior)
    agent = agent_module.new(agent_id)
    pid = spawn_link(fn -> agent_holder_loop(agent) end)
    {:ok, pid}
  end
end
```

### Tracking Reviews Across Signals

**Coordinator must correlate signals**:
- `review.request` starts a review
- Multiple `review.result` signals (one per specialist)
- Emit `review.summary` when all results collected

**Use `subject` field for correlation**:
```elixir
# All signals for same review share subject
subject = "jido://review/#{review_id}"

# Coordinator can track by subject or review_id
```

## Test Structure (TDD)

### PerformanceAgentServer Tests

```elixir
# test/synapse/agents/performance_agent_server_test.exs
defmodule Synapse.Agents.PerformanceAgentServerTest do
  use ExUnit.Case, async: false

  test "starts and subscribes to review.request" do
    {:ok, pid} = PerformanceAgentServer.start_link(id: "perf_test", bus: :synapse_bus)
    # ... assertions
  end

  test "processes review request and emits result" do
    {:ok, _pid} = PerformanceAgentServer.start_link(...)

    # Subscribe to results
    {:ok, _} = Jido.Signal.Bus.subscribe(:synapse_bus, "review.result", ...)

    # Publish request with high complexity code
    {:ok, signal} = Jido.Signal.new(%{
      type: "review.request",
      data: %{review_id: "...", diff: complex_code_diff, ...}
    })

    Jido.Signal.Bus.publish(:synapse_bus, [signal])

    # Assert result received
    assert_receive {:signal, result}, 2000
    assert result.type == "review.result"
    assert result.data.agent == "performance_specialist"
    assert length(result.data.findings) > 0  # Should detect complexity
  end
end
```

### CoordinatorAgentServer Tests

```elixir
# test/synapse/agents/coordinator_agent_server_test.exs
defmodule Synapse.Agents.CoordinatorAgentServerTest do
  use ExUnit.Case, async: false

  test "spawns specialists on review.request" do
    {:ok, coordinator_pid} = CoordinatorAgentServer.start_link(
      id: "coordinator_test",
      bus: :synapse_bus
    )

    # Publish review request
    {:ok, signal} = Jido.Signal.new(%{type: "review.request", ...})
    Jido.Signal.Bus.publish(:synapse_bus, [signal])

    # Give time for spawning
    Process.sleep(100)

    # Verify specialists were spawned
    {:ok, security_pid} = Synapse.AgentRegistry.lookup(:synapse_registry, "security_specialist")
    {:ok, perf_pid} = Synapse.AgentRegistry.lookup(:synapse_registry, "performance_specialist")

    assert Process.alive?(security_pid)
    assert Process.alive?(perf_pid)
  end

  test "aggregates results and emits summary" do
    {:ok, _coordinator_pid} = CoordinatorAgentServer.start_link(...)

    # Subscribe to summary
    {:ok, _} = Jido.Signal.Bus.subscribe(:synapse_bus, "review.summary", ...)

    # Publish request
    # (This will trigger spawn → process → results → summary)
    {:ok, signal} = Jido.Signal.new(%{type: "review.request", ...})
    Jido.Signal.Bus.publish(:synapse_bus, [signal])

    # Wait for summary
    assert_receive {:signal, summary_signal}, 5000
    assert summary_signal.type == "review.summary"
    assert summary_signal.data.status == :complete
    assert length(summary_signal.data.findings) > 0
    assert summary_signal.data.metadata.specialists_resolved == [
      "security_specialist",
      "performance_specialist"
    ]
  end
end
```

### Full Integration Test

```elixir
# test/synapse/integration/stage_2_orchestration_test.exs
defmodule Synapse.Integration.Stage2OrchestrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "complete multi-agent review orchestration" do
    # Start coordinator
    {:ok, _coordinator} = CoordinatorAgentServer.start_link(
      id: "coordinator_integration",
      bus: :synapse_bus
    )

    # Subscribe to summary
    {:ok, _} = Jido.Signal.Bus.subscribe(:synapse_bus, "review.summary", ...)

    # Publish request with both security AND performance issues
    {:ok, request} = Jido.Signal.new(%{
      type: "review.request",
      source: "/integration/test",
      data: %{
        review_id: "integration_full_001",
        diff: """
        #{DiffSamples.sql_injection_diff()}
        #{DiffSamples.high_complexity_diff()}
        """,
        files_changed: 5,
        labels: ["security", "performance"],
        intent: "feature",
        metadata: %{...}
      }
    })

    Jido.Signal.Bus.publish(:synapse_bus, [request])

    # Wait for summary
    assert_receive {:signal, summary}, 5000

    # Verify complete orchestration
    assert summary.type == "review.summary"
    assert summary.data.review_id == "integration_full_001"
    assert summary.data.status == :complete

    # Should have findings from BOTH specialists
    findings = summary.data.findings
    security_findings = Enum.filter(findings, &(&1.type in [:sql_injection, :xss, :auth_bypass]))
    performance_findings = Enum.filter(findings, &(&1.type in [:high_complexity, :memory_hotspot]))

    assert length(security_findings) > 0, "Should have security findings"
    assert length(performance_findings) > 0, "Should have performance findings"

    # Verify both specialists resolved
    assert "security_specialist" in summary.data.metadata.specialists_resolved
    assert "performance_specialist" in summary.data.metadata.specialists_resolved
  end
end
```

## Success Metrics

### Test Metrics

- **Target**: ~190 total tests (161 + ~30 new)
- **Requirement**: 0 failures, 0 compilation warnings
- **Integration**: Full flow test passing

### Functional Metrics

```elixir
# This must work:
iex -S mix
iex> Stage2Demo.run()

# Output must show:
# - Coordinator starting
# - Specialists spawning
# - Both processing signals
# - Results aggregating
# - Summary emitted
# - Success message

# Verification:
{:ok, "✓ Multi-agent orchestration complete"}
```

### Quality Metrics

```bash
mix precommit
# Expected:
# - mix compile: ✓ No warnings
# - mix format: ✓ All formatted
# - mix dialyzer: ✓ Clean (except known Jido warnings)
# - mix test: ✓ ~190/190 passing
```

## Files to Create

**Minimum Required**:
1. `lib/synapse/agents/performance_agent_server.ex` (~180 lines)
2. `lib/synapse/agents/coordinator_agent_server.ex` (~300 lines)
3. `lib/synapse/examples/stage_2_demo.ex` (~250 lines)
4. `test/synapse/agents/performance_agent_server_test.exs` (~100 lines)
5. `test/synapse/agents/coordinator_agent_server_test.exs` (~200 lines)
6. `test/synapse/integration/stage_2_orchestration_test.exs` (~150 lines)
7. `docs/20251028/multi_agent_framework/stage_2/README.md`
8. `docs/20251028/multi_agent_framework/stage_2/GETTING_STARTED.md`

**Modifications**:
- `lib/synapse/agent_registry.ex` - Support GenServer spawning
- `docs/20251028/multi_agent_framework/README.md` - Add Stage 2 status
- `docs/20251028/multi_agent_framework/ARCHITECTURE.md` - Update diagrams
- `docs/20251028/multi_agent_framework/API_REFERENCE.md` - New APIs

**Estimate**: ~1,200 lines of new code + tests + docs

## Common Pitfalls to Avoid

1. **Don't use Process.whereis** - Jido.Signal.Bus uses custom registration
2. **Don't forget cleanup** - Unsubscribe in terminate/2
3. **Don't mix sync/async** - Use async dispatch in tests
4. **Don't hardcode timeouts** - Specialists may take 100-500ms
5. **Don't skip test cleanup** - Stop all agents in on_exit
6. **Don't forget state updates** - Agents must evolve their state
7. **Don't skip documentation** - Every new function needs @doc

## Verification Checklist

Before considering Stage 2 complete:

- [ ] PerformanceAgentServer GenServer: ✓ Working, ✓ Tested
- [ ] CoordinatorAgentServer GenServer: ✓ Working, ✓ Tested
- [ ] Directive.Spawn processing: ✓ Working, ✓ Tested
- [ ] Multi-agent aggregation: ✓ Working, ✓ Tested
- [ ] Full integration test: ✓ Passing
- [ ] Stage2Demo.run(): ✓ Working, ✓ Observable
- [ ] All existing tests: ✓ Still passing
- [ ] mix precommit: ✓ Clean
- [ ] Documentation: ✓ Complete (README, guides, inline docs)
- [ ] Signal contracts: ✓ All three signals implemented
- [ ] AgentRegistry: ✓ Spawns GenServers correctly

## Expected Outcome

After Stage 2, you will have:

```
┌──────────────────┐
│ review.request   │
└────────┬─────────┘
         ↓
┌─────────────────────────┐
│ CoordinatorAgentServer  │
│ (GenServer)             │
└───┬─────────────────┬───┘
    │                 │
    ↓ Directive.Spawn ↓
┌───────────┐    ┌────────────┐
│ Security  │    │Performance │
│ Agent     │    │Agent       │
│(GenServer)│    │(GenServer) │
└─────┬─────┘    └──────┬─────┘
      │                 │
      ↓ review.result   ↓
┌─────────────────────────┐
│ CoordinatorAgentServer  │
│ (aggregates)            │
└────────┬────────────────┘
         ↓
┌──────────────────┐
│ review.summary   │
└──────────────────┘
```

**A fully autonomous, multi-agent code review system communicating via signals.**

## Start Here

```bash
# 1. Verify Stage 0/1 working
iex -S mix
iex> Synapse.Examples.Stage0Demo.run()
# Should work ✓

# 2. Read required docs (in order listed above)

# 3. Start TDD:
# Write first failing test for PerformanceAgentServer
# Follow the test → implement → verify cycle

# 4. Keep mix precommit green at every step

# 5. Build Stage2Demo as you go to verify integration
```

## Questions to Answer During Implementation

- How does coordinator know which specialists to spawn? (Classification result)
- How does coordinator track which specialists responded? (active_reviews state)
- How does coordinator know all results are in? (pending_specialists list empty)
- What happens if a specialist doesn't respond? (Timeout, emit failed summary)
- How do we prevent duplicate specialist spawning? (AgentRegistry.get_or_spawn)

**All answers should come from the code you write and tests that prove it.**

---

**Ready to build Stage 2? Follow this prompt strictly. TDD all the way.** 🚀

**Success = Full multi-agent orchestration working end-to-end with all tests passing.**
