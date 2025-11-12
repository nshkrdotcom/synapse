# Jido Enhancement Design Document

**Date:** 2025-10-28
**Status:** Planning
**Objective:** Enhance Synapse's usage of Jido framework features

---

## Overview

This document outlines planned enhancements to Synapse's Jido framework integration, prioritized by value/effort ratio and organized into high, medium, and low priority tiers.

**Guiding Principles:**
1. Enhance existing functionality without breaking changes
2. Add value incrementally (not for framework's sake)
3. Maintain test coverage throughout
4. Document architectural decisions
5. Use TDD for all implementations

---

## High Priority Enhancements

### HP-1: Formalize Workflows with Chain.chain

**Problem:**
Manual orchestration in ReviewOrchestrator uses verbose `with` constructs and lacks automatic error handling/retry capabilities.

**Current Implementation:**
```elixir
# lib/synapse/workflows/review_orchestrator.ex:14-40
with {:ok, executor_agent, _} <- SimpleExecutor.cmd(...),
     {:ok, critic_agent, _} <- CriticAgent.cmd(...),
     {:ok, suggestion} <- request_llm_suggestion(...) do
  {:ok, %{executor_output: ..., review: ..., suggestion: ...}}
end
```

**Proposed Design:**
```elixir
defmodule Synapse.Workflows.ReviewOrchestrator do
  alias Jido.Workflow.Chain

  def evaluate(input) do
    Chain.chain(
      [
        {PrepareReview, []},
        {ExecuteCode, []},
        {CriticReview, [timeout: 10_000]},
        {GenerateCritique, [timeout: 30_000, retry: true, max_retries: 2]}
      ],
      input,
      context: %{llm_profile: input[:llm_profile]}
    )
  end
end
```

**Benefits:**
- Automatic error propagation
- Per-action timeout configuration
- Built-in retry logic
- Cleaner composition
- Better error messages

**Implementation Steps:**
1. Extract executor logic into PrepareReview action
2. Create ExecuteCode action wrapper for Echo
3. Refactor evaluate/1 to use Chain.chain
4. Add per-action timeout configuration
5. Test error scenarios with retry

**Effort:** Medium (4-6 hours)
**Value:** High (cleaner code, better error handling)
**Breaking Changes:** None (can coexist with current implementation)

**Testing Strategy:**
- Test chain execution end-to-end
- Verify per-action timeouts
- Test retry behavior on LLM failures
- Ensure error messages remain clear

---

### HP-2: Adopt JidoTest.AgentCase DSL

**Problem:**
Agent tests use verbose manual setup and assertions. No standardized agent lifecycle management in tests.

**Current Implementation:**
```elixir
# test/synapse/agents/critic_agent_test.exs:8-23
test "stores decision fossils" do
  agent = CriticAgent.new()

  {:ok, agent, _} = CriticAgent.cmd(
    agent,
    {CriticReview, %{code: "IO.puts(:ok)", intent: "print", constraints: []}}
  )

  assert agent.state.review_count == 1
  assert [%{confidence: _conf} | _] = agent.state.decision_fossils
end
```

**Proposed Design:**
```elixir
defmodule Synapse.Agents.CriticAgentTest do
  use ExUnit.Case, async: true
  use JidoTest.AgentCase

  test "stores decision fossils and review metadata" do
    spawn_agent(CriticAgent)
    |> assert_agent_state(review_count: 0, decision_fossils: [])
    |> send_signal_sync("review.code", %{
      code: "IO.puts(:ok)",
      intent: "print",
      constraints: []
    })
    |> assert_agent_state(review_count: 1)
    |> assert_queue_empty()

    state = get_agent_state(context)
    assert [%{confidence: _conf, summary: _sum}] = state.decision_fossils
  end
end
```

**Benefits:**
- Cleaner, more readable tests
- Automatic agent cleanup
- Standardized assertions
- Queue management helpers
- Better error messages

**Implementation Steps:**
1. Add `use JidoTest.AgentCase` to agent tests
2. Replace `agent.new()` with `spawn_agent(Agent)`
3. Use pipeline-style assertions
4. Add queue assertions where appropriate
5. Verify all tests pass

**Effort:** Low (2-3 hours)
**Value:** High (better test maintainability)
**Breaking Changes:** None (can migrate incrementally)

**Testing Strategy:**
- Migrate one test file at a time
- Verify behavior unchanged
- Add new queue assertions
- Document DSL usage patterns

---

### HP-3: Add Action Compensation for LLM Failures

**Problem:**
LLM requests can fail in ways that require cleanup (e.g., partial state updates, resource allocation). No compensation mechanism exists.

**Current Implementation:**
```elixir
# lib/synapse/actions/generate_critique.ex:37-50
def run(params, _context) do
  case ReqLLM.chat_completion(llm_params, profile: profile) do
    {:ok, response} -> {:ok, response}
    {:error, %Error{} = error} -> {:error, error}
    # No cleanup on error
  end
end
```

**Proposed Design:**
```elixir
defmodule Synapse.Actions.GenerateCritique do
  use Jido.Action,
    name: "generate_critique",
    compensation: [
      enabled: true,
      max_retries: 2,
      timeout: 5_000
    ],
    schema: [...]

  @impl true
  def run(params, context) do
    # Track request for cleanup
    request_id = start_request_tracking(params, context)

    case ReqLLM.chat_completion(llm_params, profile: profile) do
      {:ok, response} ->
        complete_request_tracking(request_id, :success)
        {:ok, response}
      {:error, error} ->
        complete_request_tracking(request_id, :error)
        {:error, error}
    end
  end

  @impl true
  def on_error(params, error, context, _opts) do
    Logger.warning("Compensating for LLM failure",
      error: error.message,
      profile: params.profile
    )

    # Cleanup partial state, cancel in-flight requests, etc.
    cleanup_llm_resources(params, context)

    {:ok, %{compensated: true, original_error: error}}
  end
end
```

**Benefits:**
- Automatic cleanup on failure
- Resource leak prevention
- Better error recovery
- Audit trail of compensations

**Implementation Steps:**
1. Add compensation configuration to GenerateCritique
2. Implement on_error/4 callback
3. Add request tracking mechanism
4. Add cleanup logic for partial failures
5. Test compensation scenarios

**Effort:** Medium (3-4 hours)
**Value:** Medium (better resource management)
**Breaking Changes:** None

**Testing Strategy:**
- Test successful compensation
- Verify resource cleanup
- Test compensation retries
- Ensure errors still propagate correctly

---

## Medium Priority Enhancements

### MP-1: Add Async LLM Execution

**Problem:**
LLM requests (10-minute timeout) block the entire workflow. Could benefit from async execution for better responsiveness.

**Current Implementation:**
```elixir
# Blocks for entire LLM duration
{:ok, suggestion} <- request_llm_suggestion(message, reviewer_feedback, profile)
```

**Proposed Design:**
```elixir
def evaluate_async(input) do
  # Start async LLM request early
  llm_task = Jido.Workflow.run_async(
    GenerateCritique,
    %{prompt: build_prompt(input)},
    %{},
    timeout: 600_000
  )

  # Do synchronous work
  {:ok, executor_result} = run_executor(input)
  {:ok, critic_result} = run_critic(input)

  # Wait for LLM result
  {:ok, suggestion} = Jido.Workflow.await(llm_task, 600_000)

  {:ok, combine_results(executor_result, critic_result, suggestion)}
end
```

**Benefits:**
- Better resource utilization
- Parallel execution where possible
- Reduced total latency
- Cancellation support

**Implementation Steps:**
1. Identify parallelizable workflow sections
2. Use Jido.Workflow.run_async for LLM calls
3. Add proper await/timeout handling
4. Add cancellation logic
5. Test async execution paths

**Effort:** Medium (4-5 hours)
**Value:** Medium (better performance)
**Breaking Changes:** None (add async variant)

---

### MP-2: Implement Review Quality Sensor

**Problem:**
No automated monitoring of review quality or learning pattern effectiveness.

**Proposed Design:**
```elixir
defmodule Synapse.Sensors.ReviewQualityMonitor do
  use Jido.Sensor,
    name: "review_quality_monitor",
    description: "Monitors review quality and learning patterns",
    schema: [
      check_interval: [type: :pos_integer, default: 300_000],  # 5 minutes
      confidence_threshold: [type: :float, default: 0.7]
    ]

  @impl true
  def mount(opts) do
    state = %{
      id: opts.id,
      target: opts.target,
      config: opts,
      last_check: DateTime.utc_now()
    }
    {:ok, state}
  end

  @impl true
  def deliver_signal(state) do
    metrics = analyze_recent_reviews(state.last_check)

    signal = cond do
      metrics.avg_confidence < state.config.confidence_threshold ->
        quality_alert_signal(metrics)

      metrics.pattern_learning_rate > 0.8 ->
        learning_success_signal(metrics)

      true ->
        routine_report_signal(metrics)
    end

    {:ok, signal}
  end

  defp analyze_recent_reviews(since) do
    # Query review history from agents
    %{
      avg_confidence: 0.85,
      review_count: 42,
      pattern_learning_rate: 0.75,
      escalation_rate: 0.15
    }
  end
end
```

**Integration:**
```elixir
# Start sensor with CriticAgent
{:ok, _sensor} = Synapse.Sensors.ReviewQualityMonitor.start_link(
  id: "quality_monitor",
  target: {:logger, level: :info},
  check_interval: 300_000
)
```

**Benefits:**
- Automated quality tracking
- Early detection of issues
- Learning effectiveness monitoring
- Metrics for improvement

**Effort:** Medium (5-6 hours)
**Value:** Medium (better observability)

---

### MP-3: Extract Instruction Configuration

**Problem:**
No per-action configuration for timeouts/retries. All actions use same settings.

**Proposed Design:**
```elixir
defmodule Synapse.Workflows.ReviewOrchestrator do
  def evaluate_with_instructions(input) do
    instructions = [
      %Instruction{
        action: PrepareReview,
        params: Map.take(input, [:message, :intent]),
        opts: [timeout: 5_000]
      },
      %Instruction{
        action: CriticReview,
        params: %{
          code: input.message,
          intent: input.intent,
          constraints: input[:constraints] || []
        },
        opts: [timeout: 10_000]
      },
      %Instruction{
        action: GenerateCritique,
        params: %{
          prompt: build_prompt(input),
          messages: [],
          profile: input[:llm_profile]
        },
        opts: [
          timeout: 600_000,  # 10 minutes for LLM
          retry: true,
          max_retries: 2,
          backoff: 1_000
        ]
      }
    ]

    {:ok, agent} = CriticAgent.new()
    {:ok, agent, _directives} = CriticAgent.cmd(agent, instructions)

    {:ok, agent.result}
  end
end
```

**Benefits:**
- Per-action timeout control
- Granular retry configuration
- Declarative workflow definition
- Better error isolation

**Effort:** Low (2-3 hours)
**Value:** Medium (better control)

---

## Low Priority Enhancements

### LP-1: Signal-Based Architecture

**Problem:**
Synchronous function calls limit scalability and decoupling.

**Proposed Design:**
```elixir
# Convert to supervised agents with signal routing
defmodule Synapse.Agents.CriticAgent do
  use Jido.Agent,
    name: "critic"

  def start_link(opts) do
    Jido.Agent.Server.start_link(
      id: opts[:id],
      agent: __MODULE__,
      mode: :auto,
      routes: [
        {"review.request", %Instruction{
          action: CriticReview,
          opts: [timeout: 10_000]
        }},
        {"review.followup", %Instruction{
          action: DetailedReview,
          opts: [timeout: 30_000]
        }}
      ]
    )
  end

  def handle_signal(%Signal{type: "review.request"} = signal) do
    # Preprocess signal
    {:ok, signal}
  end

  def transform_result(%Signal{} = signal, result) do
    # Emit follow-up signal if confidence low
    if result.confidence < 0.7 do
      followup = Jido.Signal.new!(%{
        type: "review.followup",
        source: signal.id,
        data: result
      })

      {:ok, result, followup}  # Emit additional signal
    else
      {:ok, result}
    end
  end
end
```

**Benefits:**
- Async processing
- Event-driven workflows
- Better scalability
- Decoupled components
- Automatic retries via signal replay

**Effort:** High (8-10 hours)
**Value:** Medium (architectural flexibility)
**Breaking Changes:** Moderate (agents become processes)

**Implementation Steps:**
1. Add start_link/1 to agents
2. Define signal routes
3. Implement handle_signal/1 callbacks
4. Add signal emission logic
5. Update tests for async behavior
6. Add supervision tree configuration

---

### LP-2: Skills for Capability Bundling

**Problem:**
No logical grouping of related actions. Would benefit from reusable review capability bundles.

**Proposed Design:**
```elixir
defmodule Synapse.Skills.CodeReview do
  use Jido.Skill,
    name: "code_review",
    description: "Comprehensive code review capabilities",
    category: "review",
    tags: ["code", "quality", "critique"],
    opts_key: :code_review,
    actions: [
      Synapse.Actions.CriticReview,
      Synapse.Actions.GenerateCritique,
      Synapse.Actions.FormatSuggestion
    ],
    signals: [
      input: ["review.request.*", "code.submit.*"],
      output: ["review.complete.*", "critique.ready.*"]
    ]

  def initial_state do
    %{
      total_reviews: 0,
      avg_confidence: 0.0,
      escalation_rate: 0.0
    }
  end

  def router do
    [
      %{
        path: "review.request.urgent",
        instruction: %{action: CriticReview},
        priority: 100
      },
      %{
        path: "review.request.*",
        instruction: %{action: CriticReview},
        priority: 50
      }
    ]
  end
end

# Use in agent
defmodule Synapse.Agents.ReviewAgent do
  use Jido.Agent,
    name: "reviewer",
    skills: [Synapse.Skills.CodeReview]  # Auto-registers actions
end
```

**Benefits:**
- Reusable review capability
- Plugin architecture
- Automatic action registration
- State namespace isolation
- Signal routing included

**Effort:** Medium (5-6 hours)
**Value:** Low (organizational benefit)

---

### LP-3: Cron Sensor for Periodic Analysis

**Problem:**
No periodic analysis of review patterns or learning effectiveness.

**Proposed Design:**
```elixir
defmodule Synapse.Sensors.PeriodicAnalysis do
  use Jido.Sensor,
    name: "periodic_analysis"

  # Analyze patterns every hour
  def start_link(opts) do
    Jido.Sensors.Cron.start_link(
      id: "pattern_analyzer",
      target: {:bus, target: :review_metrics},
      jobs: [
        {:hourly_analysis, ~e"0 * * * *"e, :analyze_patterns},
        {:daily_report, ~e"0 0 * * *"e, :generate_report}
      ]
    )
  end
end
```

**Benefits:**
- Automated pattern detection
- Trend analysis
- Quality reports
- Learning effectiveness tracking

**Effort:** Low (2-3 hours)
**Value:** Low (monitoring enhancement)

---

### LP-4: Directive-Based Dynamic Workflows

**Problem:**
Workflows are static. No ability to adapt based on review results.

**Proposed Design:**
```elixir
defmodule Synapse.Actions.CriticReview do
  use Jido.Action,
    name: "critic_review"

  def run(params, _context) do
    review_result = perform_review(params)

    directives = if review_result.confidence < 0.5 do
      # Low confidence: queue additional review
      [
        %Jido.Agent.Directive.Enqueue{
          action: :detailed_review,
          params: %{code: params.code, focus_areas: review_result.issues}
        },
        %Jido.Agent.Directive.Enqueue{
          action: :escalate_to_human,
          params: %{review_id: review_result.id}
        }
      ]
    else
      # High confidence: proceed normally
      []
    end

    {:ok, review_result, directives}
  end
end
```

**Benefits:**
- Dynamic workflow adaptation
- Confidence-based escalation
- Self-modifying behavior
- Conditional action chaining

**Effort:** Medium (4-5 hours)
**Value:** Low (nice to have)

---

## Implementation Priorities

### Phase 1: Foundation (High Priority - 8-13 hours)

**Goal:** Improve existing workflows and testing

1. **HP-1: Chain.chain workflows** (4-6 hours)
   - Most immediate value
   - Better error handling
   - Cleaner composition

2. **HP-2: JidoTest.AgentCase** (2-3 hours)
   - Quick win
   - Better test maintainability
   - Foundation for future testing

3. **HP-3: Action compensation** (3-4 hours)
   - Better resource management
   - Production readiness
   - Error recovery

**Expected Outcomes:**
- ✅ Cleaner workflow code
- ✅ Better test coverage
- ✅ Improved error handling
- ✅ Resource cleanup on failures

---

### Phase 2: Monitoring (Medium Priority - 8-11 hours)

**Goal:** Add observability and quality monitoring

1. **MP-2: Quality sensor** (5-6 hours)
   - Automated monitoring
   - Pattern detection
   - Quality metrics

2. **MP-1: Async execution** (4-5 hours)
   - Better performance
   - Parallel processing
   - Reduced latency

3. **MP-3: Instruction config** (2-3 hours)
   - Per-action timeouts
   - Granular control
   - Better error isolation

**Expected Outcomes:**
- ✅ Proactive quality monitoring
- ✅ Better performance
- ✅ Granular execution control

---

### Phase 3: Architecture (Low Priority - 15-20 hours)

**Goal:** Event-driven architecture transformation

1. **LP-1: Signal-based architecture** (8-10 hours)
   - Async communication
   - Event-driven workflows
   - Better scalability

2. **LP-2: Skills implementation** (5-6 hours)
   - Capability bundling
   - Plugin architecture
   - Reusable components

3. **LP-3: Cron sensors** (2-3 hours)
   - Periodic analysis
   - Scheduled reports
   - Automated tasks

4. **LP-4: Directive workflows** (4-5 hours)
   - Dynamic adaptation
   - Self-modifying behavior
   - Conditional chaining

**Expected Outcomes:**
- ✅ Event-driven architecture
- ✅ Better scalability
- ✅ Reusable components
- ✅ Adaptive workflows

---

## Decision Matrix

| Enhancement | Effort | Value | Breaking? | Priority | Phase |
|-------------|--------|-------|-----------|----------|-------|
| Chain workflows | Medium | High | No | HIGH | 1 |
| JidoTest DSL | Low | High | No | HIGH | 1 |
| Compensation | Medium | Medium | No | HIGH | 1 |
| Quality sensor | Medium | Medium | No | MEDIUM | 2 |
| Async execution | Medium | Medium | No | MEDIUM | 2 |
| Instruction config | Low | Medium | No | MEDIUM | 2 |
| Signal architecture | High | Medium | Moderate | LOW | 3 |
| Skills | Medium | Low | No | LOW | 3 |
| Cron sensors | Low | Low | No | LOW | 3 |
| Directives | Medium | Low | No | LOW | 3 |

---

## Risk Assessment

### High Priority (Phase 1)

**Risks:**
- Minimal - all changes are additive
- Can coexist with existing code
- Incremental migration path

**Mitigation:**
- Comprehensive test coverage
- Feature flags for rollback
- Gradual adoption

### Medium Priority (Phase 2)

**Risks:**
- Async execution adds complexity
- Sensor monitoring may impact performance
- New testing patterns required

**Mitigation:**
- Performance benchmarking
- Gradual rollout
- Monitor resource usage

### Low Priority (Phase 3)

**Risks:**
- Signal architecture is a major change
- Requires rethinking agent lifecycle
- Significant testing effort

**Mitigation:**
- Proof of concept first
- Parallel implementation
- Extensive integration testing
- Rollback plan

---

## Success Criteria

### Phase 1 Success Metrics

- ✅ All workflows use Chain.chain
- ✅ All agent tests use JidoTest.AgentCase
- ✅ LLM action has compensation handler
- ✅ All tests passing
- ✅ No performance regression

### Phase 2 Success Metrics

- ✅ Quality sensor operational
- ✅ Async LLM execution working
- ✅ Per-action timeout configuration
- ✅ Metrics dashboard showing quality trends
- ✅ <50% latency reduction for parallel workflows

### Phase 3 Success Metrics

- ✅ Signal-based architecture operational
- ✅ At least one skill implemented
- ✅ Periodic analysis running
- ✅ Dynamic workflows adapting to confidence
- ✅ Event audit trail complete

---

## Non-Goals

**What we're NOT implementing:**

1. **Full Jido feature parity** - Only adopt what adds value
2. **Event sourcing** - Current state management is adequate
3. **Distributed agents** - Single-node deployment is sufficient
4. **Real-time streaming** - Batch processing is acceptable
5. **Complex multi-agent negotiation** - Current orchestration pattern works

---

## Rollback Strategy

Each enhancement must have a clear rollback path:

### Phase 1 Rollback
- Keep old workflow functions alongside new ones
- Use feature flags to toggle implementations
- Maintain backward-compatible APIs

### Phase 2 Rollback
- Sensors can be stopped independently
- Async execution has sync fallback
- Instruction config is optional

### Phase 3 Rollback
- Signal architecture can run parallel to functional
- Skills are opt-in per agent
- Directives are backward compatible

---

## Timeline Estimates

**Conservative Estimates:**

- **Phase 1 (High Priority):** 2-3 days
- **Phase 2 (Medium Priority):** 2-3 days
- **Phase 3 (Low Priority):** 4-5 days

**Total:** 8-11 days for complete adoption

**Recommended Approach:** Implement Phase 1, assess value, then decide on Phase 2/3.

---

## Appendix: Feature Comparison

### Actions: Current vs. Enhanced

| Aspect | Current | Enhanced |
|--------|---------|----------|
| Error handling | {:error, reason} | on_error/4 compensation |
| Execution | Sync only | Async available |
| Retries | Manual | Built-in |
| Timeouts | Global | Per-action |
| Metadata | Minimal | Rich (category/tags) |

### Agents: Current vs. Enhanced

| Aspect | Current | Enhanced |
|--------|---------|----------|
| Lifecycle | Stateless structs | Supervised GenServers |
| Communication | Function calls | Signal-based |
| State | Ephemeral | Persistent |
| Monitoring | Manual | Sensor-based |
| Capabilities | Action list | Skills bundles |

### Testing: Current vs. Enhanced

| Aspect | Current | Enhanced |
|--------|---------|----------|
| Framework | ExUnit | JidoTest.AgentCase |
| Setup | Manual | spawn_agent/1 |
| Assertions | Manual | Pipeline DSL |
| Cleanup | Manual | Automatic |
| Queue testing | None | assert_queue_* |

---

## Conclusion

This design provides a **phased approach** to enhanced Jido adoption, prioritizing high-value improvements while avoiding unnecessary complexity. Phase 1 improvements can be implemented with **minimal risk** and **high confidence**, providing immediate value. Phases 2-3 should be evaluated based on Phase 1 outcomes and evolving requirements.

**Recommendation:** Begin with Phase 1 implementation using TDD approach outlined in `03_implementation_prompt.md`.
