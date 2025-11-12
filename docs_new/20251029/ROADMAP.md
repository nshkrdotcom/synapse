# Synapse Development Roadmap
**Version**: 2.0
**Last Updated**: October 29, 2025
**Current Stage**: 2 Complete
**Next Stage**: 3 (Q1 2026)

---

## Overview

This roadmap outlines the development path from the current multi-agent system to a world-class agentic platform with marketplace, learning mesh, and planetary scale capabilities.

### Stages Summary

| Stage | Name | Status | Duration | Complexity |
|-------|------|--------|----------|------------|
| **0** | Foundation | ✅ Complete | 2 weeks | Low |
| **1** | Components | ✅ Complete | 3 weeks | Medium |
| **2** | Orchestration | ✅ Complete | 4 weeks | High |
| **LLM** | Integration | ✅ Complete | 1 week | Medium |
| **3** | Advanced Features | 📋 Planned | 4-6 weeks | High |
| **4** | Marketplace | 🔮 Future | 8-10 weeks | Very High |
| **5** | Learning Mesh | 🔮 Future | 10-12 weeks | Very High |
| **6** | Planetary Scale | 🔮 Future | 12-16 weeks | Extreme |

---

## Stage 0: Foundation ✅ COMPLETE

**Completed**: 2025-10
**Duration**: 2 weeks

### Deliverables
- [x] Signal.Bus in supervision tree
- [x] Security specialist config (declarative entry in `priv/orchestrator_agents.exs`)
- [x] AgentRegistry for process tracking
- [x] Signal subscription/emission
- [x] Live demo working
- [x] 5 integration tests

### Files Delivered
- `priv/orchestrator_agents.exs` (security_specialist spec)
- `lib/synapse/agent_registry.ex` (217 lines)
- `lib/synapse/examples/stage_0_demo.ex` (223 lines)
- `test/synapse/integration/review_signal_flow_test.exs`

### Key Learnings
- Signal bus patterns work well
- GenServer wrapping stateless agents is effective
- Async signal delivery prevents blocking

---

## Stage 1: Core Components ✅ COMPLETE

**Completed**: 2025-10
**Duration**: 3 weeks

### Deliverables
- [x] 8 Actions (Review, Security, Performance)
- [x] 3 declarative agent configs (coordinator, security, performance) in `priv/orchestrator_agents.exs`
- [x] State management (history, patterns, scar tissue) defined via config `state_schema`
- [x] Integration tests for workflows
- [x] 156 unit + integration tests

### Files Delivered
- `lib/synapse/actions/` (11 action files)
- `priv/orchestrator_agents.exs` (orchestrator + specialist specs)
- Full test coverage for all actions

### Metrics
- **Actions**: 8 total
- **Test Coverage**: 100% for actions, ~90% for agents
- **Lines of Code**: ~2,000

---

## Stage 2: Multi-Agent Orchestration ✅ COMPLETE

**Completed**: 2025-10
**Duration**: 4 weeks

### Deliverables
- [x] Declarative coordinator config in `priv/orchestrator_agents.exs`
- [x] Performance specialist config (declarative entry in `priv/orchestrator_agents.exs`)
- [x] Multi-specialist coordination driven by `Synapse.Orchestrator.Runtime`
- [x] Dynamic specialist spawning via orchestration DSL
- [x] Result aggregation + negotiation hooks
- [x] Full signal flow (request → result → summary)
- [x] 16 new tests
- [x] Stage2Demo observable execution

### Files Delivered
- `priv/orchestrator_agents.exs` (coordinator + specialists)
- `lib/synapse/orchestrator/actions/run_config.ex`
- `lib/synapse/orchestrator/runtime.ex`
- `lib/synapse/examples/stage_2_demo.ex` (302 lines)
- `test/synapse/integration/stage_2_orchestration_test.exs`

### Metrics
- **Total Tests**: 177 passing, 0 failures
- **Performance**: 50-100ms full orchestration
- **Lines Added**: ~1,800 (code + tests + docs)

### Orchestrator Enhancement (Partial)
- [x] AgentConfig with NimbleOptions validation
- [x] Runtime GenServer with reconciliation
- [x] Skill system with lazy loading
- [x] AgentFactory (simplified)
- [ ] Full Jido.Agent.Server integration
- [ ] Hot reload configuration
- [ ] Agent discovery API

---

## LLM Integration ✅ COMPLETE

**Completed**: 2025-10-29
**Duration**: 1 week

### Deliverables
- [x] ReqLLM multi-provider client
- [x] Gemini provider adapter
- [x] OpenAI provider adapter
- [x] System prompt management
- [x] Retry logic with exponential backoff
- [x] Telemetry events
- [x] Live API verification (Gemini)

### Files Delivered
- `lib/synapse/req_llm.ex` (650 lines)
- `lib/synapse/providers/gemini.ex` (331 lines)
- `lib/synapse/providers/openai.ex`
- `lib/synapse/actions/generate_critique.ex` (126 lines)
- `lib/synapse/req_llm/options.ex` (283 lines)
- `lib/synapse/req_llm/system_prompt.ex`

### Metrics
- **Providers**: 2 (Gemini, OpenAI)
- **Response Time**: 200-500ms (Gemini Flash Lite)
- **Test Coverage**: 14 LLM tests, all mocked

### Verified Live
```elixir
# Gemini Flash Lite
Model: gemini-flash-lite-latest
Status: ✅ Live (verified 2025-10-29)
Latency: 200-500ms typical
Tokens: ~1000 for complex analysis
```

---

## Stage 3: Advanced Features 📋 PLANNED

**Start Date**: Q1 2026
**Duration**: 4-6 weeks
**Complexity**: High
**Priority**: Next up

### Objectives
Build resilience, observability, and learning capabilities into the existing multi-agent system.

### Feature Breakdown

#### 3.1 Timeout & Resilience (2 weeks)

**Problem**: Specialists can hang indefinitely; no circuit breakers

**Solution**:
```elixir
# Add timeout tracking inside the declarative runtime state
defmodule Synapse.Orchestrator.Timeouts do
  @specialist_timeout 5_000

  def track_deadline(state, review_id) do
    deadline = System.monotonic_time(:millisecond) + @specialist_timeout
    put_in(state, [:reviews, review_id, :metadata, :deadline], deadline)
  end

  def check_expired_reviews(state, router) do
    now = System.monotonic_time(:millisecond)

    state.reviews
    |> Enum.filter(fn {_id, review} ->
      review.pending != [] && (review.metadata[:deadline] || 0) < now
    end)
    |> Enum.reduce(state, fn {review_id, review}, acc ->
      summary = build_partial_summary(review)
      Synapse.SignalRouter.publish(router, :review_summary, summary)
      update_in(acc[:reviews], &Map.delete(&1, review_id))
    end)
  end

  defp build_partial_summary(review_state) do
    %{
      review_id: review_state.review_id,
      status: :timeout,
      severity: :unknown,
      findings: Enum.flat_map(review_state.results, & &1.findings),
      recommendations: [],
      escalations: [%{reason: :timeout}],
      metadata: Map.put(review_state.metadata, :partial, true)
    }
  end
end
```

**Deliverables**:
- [ ] Specialist timeout handling
- [ ] Circuit breaker for repeated failures
- [ ] Graceful degradation (partial results)
- [ ] Retry with backoff for transient failures

**Test Coverage**:
- Timeout scenarios
- Circuit breaker state transitions
- Partial result handling

---

#### 3.2 Telemetry & Observability (1-2 weeks)

**Problem**: Limited visibility into agent performance

**Solution**: Comprehensive telemetry + LiveView dashboard

**Telemetry Events**:
```elixir
# Agent lifecycle
[:synapse, :agent, :start]
[:synapse, :agent, :stop]
[:synapse, :agent, :crash]

# Review metrics
[:synapse, :review, :start]
[:synapse, :review, :complete]
[:synapse, :review, :timeout]
[:synapse, :review, :partial]

# Specialist metrics
[:synapse, :specialist, :spawn]
[:synapse, :specialist, :complete]
[:synapse, :specialist, :timeout]

# Finding metrics
[:synapse, :finding, :discovered]
  # Metadata: type, severity, agent, confidence
```

**LiveView Dashboard**:
```elixir
defmodule SynapseWeb.MetricsLive do
  # Real-time metrics display

  @impl true
  def mount(_params, _session, socket) do
    :telemetry.attach_many(
      "synapse-metrics",
      [
        [:synapse, :review, :complete],
        [:synapse, :agent, :crash]
      ],
      &handle_event/4,
      nil
    )

    {:ok, assign(socket, metrics: load_metrics())}
  end
end
```

**Metrics Tracked**:
- Review throughput (reviews/sec)
- Agent uptime
- Finding rates by type
- LLM API latency
- Token usage & costs
- Error rates

**Deliverables**:
- [ ] Comprehensive telemetry events
- [ ] Telemetry handler module
- [ ] LiveView metrics dashboard
- [ ] Prometheus/StatsD exporter (optional)

---

#### 3.3 Scar Tissue Learning (2 weeks)

**Problem**: Agents don't learn from failures

**Solution**: Persistent failure tracking with pattern extraction

**Architecture**:
```elixir
defmodule Synapse.ScarTissue do
  @moduledoc """
  Tracks failures and extracts learnable patterns.

  When a specialist produces a false positive or misses an issue,
  the scar tissue system records the failure and adjusts future behavior.
  """

  defstruct [
    :review_id,
    :agent_id,
    :failure_type,  # :false_positive | :false_negative | :timeout | :error
    :pattern,       # What triggered the failure
    :correction,    # What the correct behavior should have been
    :timestamp,
    :metadata
  ]

  def record_failure(agent, failure) do
    # Extract pattern from failure
    pattern = extract_pattern(failure)

    # Store in agent state
    updated_agent = update_in(agent.state.scar_tissue, fn tissue ->
      [failure | Enum.take(tissue, 49)]  # Keep last 50
    end)

    # Emit telemetry
    :telemetry.execute(
      [:synapse, :scar_tissue, :recorded],
      %{count: 1},
      %{agent: agent.id, type: failure.failure_type}
    )

    {:ok, updated_agent}
  end

  def check_against_scar_tissue(agent, candidate_finding) do
    # Check if this finding matches known false positive pattern
    matches_false_positive = Enum.any?(agent.state.scar_tissue, fn scar ->
      scar.failure_type == :false_positive and
      pattern_matches?(scar.pattern, candidate_finding)
    end)

    if matches_false_positive do
      {:skip, :known_false_positive}
    else
      {:ok, candidate_finding}
    end
  end
end
```

**Learning Flow**:
```
1. Human reviews findings → marks false positive
2. Feedback signal published: review.feedback
3. Responsible agent receives feedback
4. Agent extracts pattern from the false positive
5. Pattern stored in scar_tissue
6. Future similar findings filtered
```

**Deliverables**:
- [ ] ScarTissue data structure
- [ ] Pattern extraction logic
- [ ] Feedback signal handling
- [ ] Scar tissue checking in actions
- [ ] Persistence (ETS + periodic snapshots)
- [ ] Pattern similarity matching

---

#### 3.4 Directive.Enqueue Work Distribution (1 week)

**Problem**: Work distribution is implicit; no queue management

**Solution**: Explicit work queues with priority

**Architecture**:
```elixir
defmodule Synapse.WorkQueue do
  use GenServer

  defstruct [
    :queue_id,
    :pending,     # Priority queue of work items
    :in_progress, # Map of worker_id → work_item
    :completed,   # Circular buffer of completed items
    :workers      # Available worker pool
  ]

  def enqueue(queue_id, work_item, priority \\ :normal) do
    GenServer.call(queue_id, {:enqueue, work_item, priority})
  end

  def claim_work(queue_id, worker_id) do
    GenServer.call(queue_id, {:claim, worker_id})
  end

  def complete_work(queue_id, worker_id, result) do
    GenServer.call(queue_id, {:complete, worker_id, result})
  end
end
```

**Directive Support**:
```elixir
# In CoordinatorAgent
def classify_change(agent, review) do
  case determine_review_type(review) do
    :deep_review ->
      directives = [
        %Directive.Enqueue{
          queue: :security_queue,
          work: %{type: :security_review, review_id: review.id, diff: review.diff},
          priority: calculate_priority(review)
        },
        %Directive.Enqueue{
          queue: :performance_queue,
          work: %{type: :performance_review, review_id: review.id, diff: review.diff},
          priority: calculate_priority(review)
        }
      ]

      {:ok, agent, directives}
  end
end
```

**Deliverables**:
- [ ] WorkQueue GenServer
- [ ] Priority queue implementation
- [ ] Directive.Enqueue support
- [ ] Worker pool management
- [ ] Queue metrics/telemetry

---

### Stage 3 Metrics (Target)

| Metric | Current | Target |
|--------|---------|--------|
| **Specialist Timeout Handling** | None | 100% handled gracefully |
| **Telemetry Events** | 3 types | 15+ types |
| **Metrics Dashboard** | None | Live dashboard |
| **Scar Tissue Entries** | 0 | 50 per agent |
| **False Positive Reduction** | N/A | 20-30% |
| **Work Queue Latency** | N/A | <10ms |

### Estimated Effort
- **Engineering Time**: 4-6 weeks
- **Test Development**: 2 weeks
- **Documentation**: 1 week
- **Total**: 7-9 weeks

---

## Stage 4: Agent Marketplace 🔮 FUTURE

**Start Date**: Q2 2026
**Duration**: 8-10 weeks
**Complexity**: Very High

### Vision
Dynamic agent marketplace with reputation, pricing, and runtime registration.

### Core Features

#### 4.1 Agent Hierarchy
```elixir
defmodule Synapse.Marketplace.AgentTier do
  @type tier :: :junior | :senior | :architect | :expert

  @junior_config %{
    speed_multiplier: 1.5,      # Faster
    accuracy: 0.70,             # Less accurate
    cost_per_review: 0.001,     # Cheaper
    confidence_threshold: 0.60  # Lower bar
  }

  @senior_config %{
    speed_multiplier: 1.0,      # Normal speed
    accuracy: 0.90,             # More accurate
    cost_per_review: 0.005,     # More expensive
    confidence_threshold: 0.80  # Higher bar
  }
end
```

**Use Cases**:
- Route simple PRs to junior agents (fast, cheap)
- Route complex security changes to senior agents
- Route architecture decisions to architect agents

---

#### 4.2 Reputation System
```elixir
defmodule Synapse.Marketplace.Reputation do
  defstruct [
    agent_id: nil,
    reviews_completed: 0,
    true_positives: 0,
    false_positives: 0,
    false_negatives: 0,
    avg_response_time_ms: 0,
    user_ratings: [],  # Human feedback
    reputation_score: 0.5  # Bayesian score (0.0-1.0)
  ]

  def calculate_reputation(history) do
    accuracy = history.true_positives /
               (history.true_positives + history.false_positives + history.false_negatives)

    speed_factor = if history.avg_response_time_ms < 200, do: 1.1, else: 1.0

    user_satisfaction = Enum.sum(history.user_ratings) / length(history.user_ratings)

    # Bayesian reputation score
    0.4 * accuracy + 0.3 * speed_factor + 0.3 * user_satisfaction
  end
end
```

**Reputation Tracking**:
- Accuracy (true/false positives/negatives)
- Response time
- User feedback scores
- Historical performance

---

#### 4.3 Dynamic Pricing
```elixir
defmodule Synapse.Marketplace.Pricing do
  def calculate_cost(agent, review) do
    base_cost = agent.tier_config.cost_per_review

    # Adjust for complexity
    complexity_multiplier = estimate_complexity(review)

    # Adjust for demand
    demand_multiplier = calculate_demand(agent.id)

    # Adjust for reputation
    reputation_multiplier = agent.reputation_score

    base_cost * complexity_multiplier * demand_multiplier * reputation_multiplier
  end
end
```

---

#### 4.4 Marketplace Registration
```elixir
defmodule Synapse.Marketplace.Registry do
  def register_agent(agent_spec) do
    with {:ok, validated} <- validate_agent_spec(agent_spec),
         {:ok, capabilities} <- discover_capabilities(agent_spec),
         {:ok, _pid} <- spawn_agent(agent_spec) do

      # Add to marketplace
      :ets.insert(:agent_marketplace, {
        agent_spec.id,
        %{
          spec: validated,
          capabilities: capabilities,
          tier: agent_spec.tier,
          reputation: initial_reputation(),
          available: true
        }
      })

      {:ok, agent_spec.id}
    end
  end

  def find_agent(requirements) do
    # Match agents by capability and tier
    :agent_marketplace
    |> :ets.tab2list()
    |> Enum.filter(fn {_id, agent} ->
      matches_requirements?(agent, requirements)
    end)
    |> Enum.sort_by(fn {_id, agent} -> agent.reputation end, :desc)
    |> List.first()
  end
end
```

---

### Stage 4 Deliverables
- [ ] Agent tier system (junior/senior/architect)
- [ ] Reputation tracking and scoring
- [ ] Dynamic pricing engine
- [ ] Marketplace registry API
- [ ] Agent capability advertisement
- [ ] Matchmaking algorithm
- [ ] Cost tracking and budgets

### Estimated Effort
- **Engineering Time**: 8-10 weeks
- **Total**: 12-14 weeks with testing/docs

---

## Stage 5: Learning Mesh 🔮 FUTURE

**Start Date**: Q3 2026
**Duration**: 10-12 weeks
**Complexity**: Very High

### Vision
Distributed knowledge sharing across agent clusters.

### Core Features

#### 5.1 Pattern Library Sync
```elixir
defmodule Synapse.LearningMesh.PatternSync do
  @moduledoc """
  Synchronizes learned patterns across agent instances.

  When one SecurityAgent discovers a new vulnerability pattern,
  it broadcasts to all other SecurityAgents in the cluster.
  """

  def share_pattern(agent_id, pattern) do
    broadcast = %{
      type: "pattern.discovered",
      source_agent: agent_id,
      pattern: pattern,
      confidence: pattern.confidence,
      examples: pattern.examples,
      timestamp: DateTime.utc_now()
    }

    # Broadcast via dedicated learning channel
    Jido.Signal.Bus.publish(:learning_mesh, [broadcast])
  end

  def handle_pattern_broadcast(agent, pattern_signal) do
    # Validate pattern isn't already known
    unless pattern_exists?(agent, pattern_signal.data.pattern) do
      # Add to learned patterns with provenance
      pattern_with_meta = Map.put(pattern_signal.data.pattern, :learned_from, pattern_signal.data.source_agent)

      updated_agent = update_in(agent.state.learned_patterns, fn patterns ->
        [pattern_with_meta | patterns]
      end)

      {:ok, updated_agent}
    else
      {:ok, agent}
    end
  end
end
```

---

#### 5.2 Tool Effectiveness Tracking
```elixir
defmodule Synapse.LearningMesh.ToolEffectiveness do
  defstruct [
    tool_module: nil,
    executions: 0,
    true_positives: 0,
    false_positives: 0,
    false_negatives: 0,
    avg_execution_time_ms: 0,
    effectiveness_score: 0.5
  ]

  def track_execution(tool, result, outcome) do
    metrics = load_metrics(tool)

    updated = %{metrics |
      executions: metrics.executions + 1,
      true_positives: metrics.true_positives + if outcome == :true_positive, do: 1, else: 0,
      false_positives: metrics.false_positives + if outcome == :false_positive, do: 1, else: 0
    }

    # Recalculate effectiveness
    effectiveness = calculate_effectiveness(updated)

    %{updated | effectiveness_score: effectiveness}
  end

  def recommend_tools(agent_type, context) do
    # Get all tools for agent type
    tools = list_tools_for_agent(agent_type)

    # Filter by effectiveness threshold
    effective_tools = Enum.filter(tools, fn {tool, metrics} ->
      metrics.effectiveness_score > 0.7
    end)

    # Sort by effectiveness for this context
    Enum.sort_by(effective_tools, fn {tool, metrics} ->
      context_adjusted_score(metrics, context)
    end, :desc)
  end
end
```

**Benefits**:
- Retire ineffective tools
- Prioritize high-value checks
- Context-aware tool selection

---

#### 5.3 Cross-Agent Knowledge Sync

**Architecture**: Gossip protocol + CRDT

```elixir
defmodule Synapse.LearningMesh.GossipSync do
  @sync_interval 60_000  # Sync every minute

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    schedule_sync()

    state = %{
      node_id: Node.self(),
      peers: discover_peers(),
      knowledge_version: 0,
      last_sync: DateTime.utc_now()
    }

    {:ok, state}
  end

  def handle_info(:sync, state) do
    # Pick random peer
    peer = Enum.random(state.peers)

    # Request their knowledge state
    {their_version, their_knowledge} = :rpc.call(peer, __MODULE__, :get_knowledge, [])

    # Merge if they're ahead
    updated_state = if their_version > state.knowledge_version do
      merge_knowledge(state, their_knowledge)
    else
      state
    end

    schedule_sync()
    {:noreply, updated_state}
  end

  defp merge_knowledge(state, remote_knowledge) do
    # CRDT merge logic
    # ...
  end
end
```

---

### Stage 5 Deliverables
- [ ] Pattern library with sync
- [ ] Gossip protocol implementation
- [ ] CRDT for conflict-free merges
- [ ] Tool effectiveness tracking
- [ ] Cross-agent knowledge API
- [ ] Feedback ingestion pipeline
- [ ] Learning analytics dashboard

### Estimated Effort
- **Engineering Time**: 10-12 weeks
- **Total**: 14-16 weeks

---

## Stage 6: Planetary Scale & Self-Improvement 🔮 FUTURE

**Start Date**: Q4 2026
**Duration**: 12-16 weeks
**Complexity**: Extreme

### Vision
Massive scale + emergent intelligence

### Core Features

#### 6.1 Distributed Signal Bus (Kafka/Pulsar)
```elixir
# Partition signals by review_id
defmodule Synapse.DistributedBus do
  def publish(signal) do
    partition = :erlang.phash2(signal.data.review_id, @partition_count)

    Kafka.publish(
      topic: "synapse.signals",
      partition: partition,
      message: encode_signal(signal)
    )
  end
end
```

#### 6.2 Agent Pooling
```elixir
# Reuse agent processes across reviews
defmodule Synapse.AgentPool do
  def checkout(agent_type) do
    case :poolboy.checkout(:agent_pool, false, 100) do
      :full -> spawn_new_agent(agent_type)
      pid -> {:ok, pid}
    end
  end
end
```

#### 6.3 LLM-Generated Tools
```elixir
defmodule Synapse.ToolGenerator do
  def propose_new_tool(pattern) do
    prompt = """
    Based on this vulnerability pattern that we've seen 50+ times:

    #{inspect(pattern)}

    Generate an Elixir Jido.Action module that detects this pattern.
    Include schema validation and proper error handling.
    """

    {:ok, code} = LLM.generate(prompt)

    # Human review required
    {:ok, %ProposedTool{code: code, pattern: pattern}}
  end
end
```

---

### Stage 6 Deliverables
- [ ] Distributed signal bus (Kafka)
- [ ] Agent pooling & recycling
- [ ] Cross-repo analysis
- [ ] Multi-datacenter support
- [ ] LLM tool generation
- [ ] Reinforcement learning integration
- [ ] Emergent strategy detection

### Estimated Effort
- **Engineering Time**: 12-16 weeks
- **Research**: 4-6 weeks
- **Total**: 18-24 weeks

---

## Timeline Summary

```
2025 Q4 ████████████████████ Stage 2 Complete + LLM Integration ✅
2026 Q1 ████████████████████ Stage 3: Advanced Features
2026 Q2 ████████████████████ Stage 4: Marketplace (start)
2026 Q3 ████████████████████ Stage 4: Marketplace (complete)
2026 Q4 ████████████████████ Stage 5: Learning Mesh
2027 Q1 ████████████████████ Stage 6: Planetary Scale
```

---

## Success Metrics by Stage

| Stage | Key Metric | Target |
|-------|------------|--------|
| **3** | Specialist timeouts handled | 100% |
| **3** | False positive reduction | 20-30% |
| **3** | Metrics dashboard | Live |
| **4** | Agent marketplace | 10+ agents |
| **4** | Reputation system | Working |
| **5** | Pattern sync latency | <1min |
| **5** | Knowledge mesh nodes | 5+ clusters |
| **6** | Reviews/day | 100,000+ |
| **6** | Agent instances | 1,000+ |

---

## Risk Assessment

### Stage 3 Risks
- **Low**: Timeout handling (well-understood problem)
- **Low**: Telemetry (using existing libraries)
- **Medium**: Scar tissue learning (pattern extraction complexity)

### Stage 4 Risks
- **High**: Reputation gaming/manipulation
- **Medium**: Pricing model economics
- **High**: Security (untrusted agent code)

### Stage 5 Risks
- **Very High**: Distributed consensus at scale
- **High**: Knowledge conflicts/contradictions
- **Medium**: Network partition handling

### Stage 6 Risks
- **Extreme**: Operational complexity
- **Very High**: Cost at scale
- **Extreme**: Emergent behavior unpredictability

---

## Decision Points

### After Stage 3
**Decision**: Proceed with Marketplace (Stage 4) vs double down on core system?
- **If marketplace demand is high** → Stage 4
- **If core system needs hardening** → Revisit Stage 3

### After Stage 4
**Decision**: Focus on scale (Stage 6) vs intelligence (Stage 5)?
- **If user base is growing rapidly** → Stage 6
- **If accuracy is the bottleneck** → Stage 5

---

**Roadmap Owner**: Engineering Team
**Next Review**: Stage 3 kickoff (Q1 2026)
**Last Updated**: 2025-10-29
