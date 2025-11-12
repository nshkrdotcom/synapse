# Jido Integration Implementation Prompt

**Path:** `docs/20251028/jido_integration/03_implementation_prompt.md`
**Approach:** Test-Driven Development (TDD)
**Phases:** Incremental adoption (3 phases)

---

## Required Reading (Read Every Session)

### Mandatory Context Documents

1. **This prompt** _(refresh context each session)_
   - `docs/20251028/jido_integration/03_implementation_prompt.md`

2. **Analysis and design** _(understand current state and goals)_
   - `docs/20251028/jido_integration/01_usage_analysis.md` - Current Jido usage
   - `docs/20251028/jido_integration/02_enhancement_design.md` - Planned enhancements

3. **Jido framework documentation** _(understand available features)_
   - Provided in context: README.md, guides/getting-started.livemd
   - Key sections: Actions, Agents, Workflows, Testing

4. **Existing Synapse code** _(understand current implementation)_
   - `lib/synapse/actions/` - Current action implementations
   - `lib/synapse/agents/` - Current agent implementations
   - `lib/synapse/workflows/review_orchestrator.ex` - Current orchestration
   - `test/synapse/` - Existing test patterns

---

## Context: Current Architecture

### Codebase Structure
```
lib/synapse/
├── actions/
│   ├── echo.ex                    # Simple echo action
│   ├── critic_review.ex          # Code review with confidence scoring
│   └── generate_critique.ex      # LLM integration
├── agents/
│   ├── simple_executor.ex        # Tracks execution count
│   └── critic_agent.ex           # Review history, learning patterns
├── workflows/
│   └── review_orchestrator.ex    # Manual orchestration
└── providers/                     # LLM provider adapters (not Jido)
```

### Current Workflow Flow
```
User Request
    ↓
ReviewOrchestrator.evaluate/1
    ↓
SimpleExecutor.cmd(Echo action)
    ↓
CriticAgent.cmd(CriticReview action)
    ↓
Jido.Exec.run(GenerateCritique action)
    ↓
Return aggregated results
```

### Key Characteristics
- **Stateless agents** (ephemeral structs, not GenServers)
- **Synchronous execution** (function calls, not signals)
- **Manual orchestration** (with constructs, not Chain.chain)
- **Basic Jido usage** (Actions, Agents, Exec, Error only)

---

## Implementation Instructions

### General TDD Process

For each enhancement:

1. **RED: Write failing tests first**
   - Test the desired behavior
   - Verify test fails for the right reason
   - Ensure test is specific and focused

2. **GREEN: Implement minimal code to pass**
   - Write only enough code to make test pass
   - Avoid over-engineering
   - Keep it simple

3. **REFACTOR: Clean up**
   - Remove duplication
   - Improve naming
   - Extract helpers
   - Update documentation

4. **VERIFY: Integration check**
   - Run full test suite
   - Check for regressions
   - Verify no breaking changes
   - Update related tests

---

## Phase 1: Foundation (High Priority)

### Objective
Improve existing workflows and testing with minimal risk.

**Deliverables:**
- Workflow Chain implementation
- JidoTest.AgentCase migration
- LLM compensation handler

**Success Criteria:**
- All existing tests pass
- New tests cover new functionality
- No performance regression
- Documentation updated

---

### HP-1: Formalize Workflows with Chain.chain

#### Step 1: RED - Write Failing Tests

**File:** `test/synapse/workflows/chain_orchestrator_test.exs` (new file)

```elixir
defmodule Synapse.Workflows.ChainOrchestratorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Synapse.Workflows.ChainOrchestrator

  setup context do
    Req.Test.set_req_test_from_context(context)
    # Setup LLM test configuration (copy from existing tests)
    # ...
  end

  describe "chain-based evaluation" do
    test "executes complete review workflow", %{gemini_stub: stub} do
      # Setup LLM stub
      Req.Test.expect(stub, fn conn ->
        Req.Test.json(conn, %{
          candidates: [%{content: %{parts: [%{text: "Good code"}]}}]
        })
      end)

      input = %{
        message: "def foo, do: :ok",
        intent: "Define function",
        constraints: []
      }

      {:ok, result} = ChainOrchestrator.evaluate(input)

      # Verify chain executed all steps
      assert result.executor_output != nil
      assert result.review != nil
      assert result.suggestion != nil
      assert result.audit_trail.review_count == 1
    end

    test "handles chain failures gracefully", %{gemini_stub: stub} do
      Req.Test.expect(stub, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{error: %{message: "Server error"}})
      end)

      input = %{message: "code", intent: "test", constraints: []}

      # Should fail with descriptive error
      assert {:error, error} = ChainOrchestrator.evaluate(input)
      assert error.type == :execution_error
    end

    test "applies per-action timeouts", %{gemini_stub: stub} do
      # Test that LLM action respects its 600s timeout
      # while other actions use shorter timeouts
    end

    test "retries LLM failures automatically", %{gemini_stub: stub} do
      # First call fails, second succeeds
      Req.Test.expect(stub, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{error: %{message: "Temporary error"}})
      end)

      Req.Test.expect(stub, fn conn ->
        Req.Test.json(conn, %{
          candidates: [%{content: %{parts: [%{text: "Success"}]}}]
        })
      end)

      # Should retry and succeed
      {:ok, result} = ChainOrchestrator.evaluate(input)
      assert result.suggestion.content == "Success"
    end
  end
end
```

**Verify test fails:** `mix test test/synapse/workflows/chain_orchestrator_test.exs`

---

#### Step 2: GREEN - Implement ChainOrchestrator

**File:** `lib/synapse/workflows/chain_orchestrator.ex` (new file)

```elixir
defmodule Synapse.Workflows.ChainOrchestrator do
  @moduledoc """
  Chain-based review orchestrator using Jido.Workflow.Chain.

  Implements the executor → critic → LLM pipeline using declarative
  chain composition with automatic error handling and retry logic.
  """

  alias Jido.Workflow.Chain
  alias Synapse.Actions.{Echo, CriticReview, GenerateCritique}

  @doc """
  Evaluates code through the review pipeline using Chain.chain.

  ## Parameters

    * `input` - Map with:
      - `:message` - Code to review (required)
      - `:intent` - What the code should do (required)
      - `:constraints` - Review constraints (optional)
      - `:llm_profile` - LLM provider to use (optional)

  ## Returns

    * `{:ok, result}` - Complete review results
    * `{:error, error}` - Execution failure
  """
  def evaluate(input) do
    %{message: message, intent: intent} = input
    constraints = Map.get(input, :constraints, [])
    llm_profile = Map.get(input, :llm_profile)

    # Build prompt for LLM
    prompt = build_llm_prompt(message, constraints)

    # Define chain with per-action configuration
    chain = [
      # Step 1: Echo (executor simulation)
      {Echo, %{message: message}},

      # Step 2: Critic review (10s timeout)
      {CriticReview, %{
        code: message,
        intent: intent,
        constraints: constraints
      }},

      # Step 3: LLM critique (10min timeout, retry enabled)
      {GenerateCritique, %{
        prompt: prompt,
        messages: [
          %{role: "system", content: "You are assisting a software engineer with rapid iteration."}
        ],
        profile: llm_profile
      }}
    ]

    # Execute chain with context
    case Chain.chain(
      chain,
      %{},  # Initial params (each action has its own)
      context: %{
        llm_profile: llm_profile,
        request_id: generate_request_id()
      },
      action_opts: %{
        Echo => [timeout: 5_000],
        CriticReview => [timeout: 10_000],
        GenerateCritique => [timeout: 600_000, retry: true, max_retries: 2]
      }
    ) do
      {:ok, results} ->
        # Extract results from chain execution
        format_chain_results(results, input)

      {:error, _reason} = error ->
        error
    end
  end

  defp build_llm_prompt(message, constraints) do
    constraint_text = if Enum.empty?(constraints) do
      ""
    else
      "\nConstraints: #{Enum.join(constraints, ", ")}"
    end

    """
    Provide concrete next steps to strengthen this code submission.

    Code:
    #{message}
    #{constraint_text}
    """
  end

  defp format_chain_results(results, original_input) do
    # Results is a map with each action's output
    # Extract and format appropriately
    {:ok, %{
      executor_output: Map.get(results, Echo),
      review: Map.get(results, CriticReview),
      suggestion: Map.get(results, GenerateCritique),
      audit_trail: %{
        review_count: 1,  # Updated based on actual chain execution
        decision_fossils: []
      }
    }}
  end

  defp generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end
end
```

**Verify test passes:** `mix test test/synapse/workflows/chain_orchestrator_test.exs`

---

#### Step 3: REFACTOR - Clean Up

1. **Extract helpers:**
```elixir
defmodule Synapse.Workflows.ChainHelpers do
  def build_review_chain(message, intent, constraints, llm_profile) do
    # Extracted chain building logic
  end

  def format_chain_results(results, original_input) do
    # Extracted formatting logic
  end
end
```

2. **Add documentation:**
   - Update module docs
   - Add @doc for public functions
   - Add examples

3. **Update existing code:**
   - Add deprecation notice to ReviewOrchestrator
   - Provide migration guide

---

#### Step 4: VERIFY - Integration

1. **Run full test suite:** `mix test`
2. **Check for regressions** in existing ReviewOrchestrator tests
3. **Update integration tests** to use new ChainOrchestrator
4. **Benchmark performance** (should be similar or better)

---

### HP-2: Adopt JidoTest.AgentCase DSL

#### Step 1: RED - Rewrite One Test with DSL

**File:** `test/synapse/agents/critic_agent_with_dsl_test.exs` (new file)

```elixir
defmodule Synapse.Agents.CriticAgentWithDSLTest do
  use ExUnit.Case, async: true
  use JidoTest.AgentCase

  alias Synapse.Agents.CriticAgent
  alias Synapse.Actions.CriticReview

  describe "review workflow with DSL" do
    test "stores decision fossils using AgentCase DSL" do
      spawn_agent(CriticAgent)
      |> assert_agent_state(review_count: 0, decision_fossils: [])
      |> send_signal_sync("execute_review", %{
        action: CriticReview,
        params: %{
          code: "IO.puts(:ok)",
          intent: "print",
          constraints: []
        }
      })
      |> assert_agent_state(review_count: 1)
      |> assert_queue_empty()

      # Check decision fossils were created
      state = get_agent_state(context)
      assert [%{confidence: _conf, summary: _sum}] = state.decision_fossils
    end

    test "maintains circular buffer for review history" do
      context = spawn_agent(CriticAgent)

      # Add 150 reviews (exceeds buffer size of 100)
      Enum.each(1..150, fn i ->
        context = send_signal_sync(context, "review", %{
          action: CriticReview,
          params: %{code: "code_#{i}", intent: "test", constraints: []}
        })
      end)

      # Should only keep last 100
      state = get_agent_state(context)
      assert length(state.review_history) == 100
    end

    test "learns from corrections" do
      spawn_agent(CriticAgent)
      |> assert_agent_state(learned_patterns: [])

      # Agent learning happens via custom methods, not signals yet
      # This test documents expected behavior once signal-based
    end
  end
end
```

**Note:** This test will fail because:
1. AgentCase expects agents to be GenServers (start_link)
2. Current agents are stateless structs
3. send_signal_sync expects signal-based communication

**Decision Point:** Either:
- **Option A:** Convert agents to GenServer pattern first (enables full DSL)
- **Option B:** Use DSL with manual agent creation (partial adoption)

**Recommended:** Option B for Phase 1, Option A for Phase 3

---

#### Step 2: GREEN - Partial DSL Adoption

**File:** `test/synapse/agents/critic_agent_test.exs` (update existing)

```elixir
defmodule Synapse.Agents.CriticAgentTest do
  use ExUnit.Case, async: true
  # Add AgentCase for helper functions (not full DSL yet)
  import JidoTest.AgentCase, only: [assert_agent_state: 2]

  alias Synapse.Agents.CriticAgent
  alias Synapse.Actions.CriticReview

  describe "CriticAgent state tracking" do
    test "stores decision fossils and review metadata" do
      agent = CriticAgent.new()

      {:ok, agent, _} = CriticAgent.cmd(
        agent,
        {CriticReview, %{code: "IO.puts(:ok)", intent: "print", constraints: []}}
      )

      # Use AgentCase helper for cleaner assertions
      assert_agent_state(agent, review_count: 1)
      assert_agent_state(agent, %{review_count: 1})

      assert [%{confidence: _conf, escalated: _esc, summary: summary} | _] =
               agent.state.decision_fossils

      assert is_binary(summary)
      assert summary != ""
    end

    # Add more tests with AgentCase helpers...
  end
end
```

**Verify:** Tests should pass with helper functions

---

#### Step 3: REFACTOR - Migrate All Agent Tests

Incrementally update each test file to use AgentCase helpers:

1. `test/synapse/agents/simple_executor_test.exs`
2. `test/synapse/agents/critic_agent_test.exs`
3. `test/synapse/workflows/*_test.exs`

**Checklist per file:**
- [ ] Import AgentCase helpers
- [ ] Replace manual assertions with DSL
- [ ] Add queue assertions where relevant
- [ ] Verify tests pass
- [ ] Update test documentation

---

#### Step 4: VERIFY - Full Suite

1. **Run:** `mix test`
2. **Verify:** All 57+ tests pass
3. **Check:** No regressions
4. **Document:** Update test README with DSL patterns

---

### HP-3: Add Action Compensation for LLM Failures

#### Step 1: RED - Write Compensation Tests

**File:** `test/synapse/actions/generate_critique_test.exs` (new file)

```elixir
defmodule Synapse.Actions.GenerateCritiqueTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Synapse.Actions.GenerateCritique

  setup context do
    Req.Test.set_req_test_from_context(context)

    stub = :"generate_critique_test_#{inspect(context.test)}"

    Application.put_env(:synapse, Synapse.ReqLLM,
      profiles: %{
        test: [
          base_url: "https://test.llm",
          api_key: "test-key",
          model: "test-model",
          plug: {Req.Test, stub},
          plug_owner: self()
        ]
      }
    )

    %{stub: stub}
  end

  describe "compensation on failure" do
    test "compensates when LLM request fails", %{stub: stub} do
      Req.Test.expect(stub, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{error: %{message: "Server error"}})
      end)

      params = %{
        prompt: "test prompt",
        messages: [],
        profile: :test
      }

      # Action should fail
      assert {:error, error} = GenerateCritique.run(params, %{})

      # Compensation should run
      assert {:ok, compensated} = GenerateCritique.on_error(
        params,
        error,
        %{request_id: "test_req"},
        []
      )

      assert compensated.compensated == true
      assert compensated.original_error != nil
    end

    test "tracks compensation attempts" do
      # Test that compensation is retried if it fails
      # Test compensation timeout handling
    end

    test "logs compensation events" do
      # Verify proper logging during compensation
    end
  end
end
```

**Verify test fails:** `mix test test/synapse/actions/generate_critique_test.exs`

---

#### Step 2: GREEN - Implement Compensation

**File:** `lib/synapse/actions/generate_critique.ex` (update existing)

```elixir
defmodule Synapse.Actions.GenerateCritique do
  use Jido.Action,
    name: "generate_critique",
    description: "Uses an LLM (via Req) to produce review suggestions",
    compensation: [
      enabled: true,
      max_retries: 2,
      timeout: 5_000
    ],
    schema: [
      prompt: [type: :string, required: true, doc: "Primary user prompt"],
      messages: [type: {:list, :map}, default: []],
      temperature: [type: {:or, [:float, nil]}, default: nil],
      max_tokens: [type: {:or, [:integer, nil]}, default: nil],
      profile: [type: {:or, [:atom, :string]}, default: nil]
    ]

  alias Jido.Error
  alias Synapse.ReqLLM

  require Logger

  @impl true
  def run(params, context) do
    llm_params = Map.take(params, [:prompt, :messages, :temperature, :max_tokens])
    profile = Map.get(params, :profile)

    # Track request for potential cleanup
    request_id = Map.get(context, :request_id, generate_request_id())

    Logger.debug("Starting LLM request",
      request_id: request_id,
      profile: profile
    )

    case ReqLLM.chat_completion(llm_params, profile: profile) do
      {:ok, response} ->
        Logger.debug("LLM request succeeded", request_id: request_id)
        {:ok, response}

      {:error, %Error{} = error} ->
        Logger.warning("LLM request failed",
          request_id: request_id,
          error: error.message
        )
        {:error, error}

      {:error, other} ->
        {:error, Error.execution_error("LLM request failed", %{reason: other})}
    end
  end

  @impl true
  def on_error(failed_params, error, context, _opts) do
    request_id = Map.get(context, :request_id, "unknown")

    Logger.warning("Compensating for LLM failure",
      request_id: request_id,
      error: error.message,
      profile: failed_params[:profile]
    )

    # Cleanup logic:
    # - Cancel any in-flight HTTP requests (if possible)
    # - Clear request tracking
    # - Emit failure metrics

    cleanup_llm_resources(failed_params, context)

    {:ok, %{
      compensated: true,
      original_error: %{
        type: error.type,
        message: error.message
      },
      compensated_at: DateTime.utc_now()
    }}
  end

  defp cleanup_llm_resources(_params, _context) do
    # Placeholder for actual cleanup logic
    # Could cancel HTTP requests, clear caches, etc.
    :ok
  end

  defp generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end
end
```

**Verify test passes:** `mix test test/synapse/actions/generate_critique_test.exs`

---

#### Step 3: REFACTOR

1. Extract request tracking to separate module
2. Add telemetry for compensation events
3. Document compensation behavior
4. Update action documentation

---

#### Step 4: VERIFY

1. Run full suite: `mix test`
2. Verify existing GenerateCritique usage still works
3. Check that errors are properly compensated
4. Ensure no performance regression

---

## Phase 2: Monitoring (Medium Priority)

### MP-2: Quality Sensor Implementation

#### TDD Steps

**Step 1: RED - Write Sensor Tests**

**File:** `test/synapse/sensors/quality_monitor_test.exs`

```elixir
defmodule Synapse.Sensors.QualityMonitorTest do
  use ExUnit.Case, async: false

  alias Synapse.Sensors.ReviewQualityMonitor

  describe "quality monitoring" do
    test "emits quality report signal" do
      {:ok, _sensor} = ReviewQualityMonitor.start_link(
        id: "test_monitor",
        target: {:pid, target: self()},
        check_interval: 100  # Fast for testing
      )

      # Should receive quality report
      assert_receive {:signal, {:ok, signal}}, 500
      assert signal.type == "review.quality.report"
      assert %{avg_confidence: _, review_count: _} = signal.data
    end

    test "detects low quality patterns" do
      # Test alert emission when quality drops
    end

    test "tracks learning effectiveness" do
      # Test pattern learning rate monitoring
    end
  end
end
```

**Step 2: GREEN - Implement Sensor**

**File:** `lib/synapse/sensors/review_quality_monitor.ex`

```elixir
defmodule Synapse.Sensors.ReviewQualityMonitor do
  use Jido.Sensor,
    name: "review_quality_monitor",
    description: "Monitors review quality metrics and learning patterns",
    category: :monitoring,
    tags: [:review, :quality, :metrics],
    schema: [
      check_interval: [type: :pos_integer, default: 300_000],
      confidence_threshold: [type: :float, default: 0.7]
    ]

  require Logger

  @impl true
  def mount(opts) do
    state = %{
      id: opts.id,
      target: opts.target,
      config: %{
        check_interval: opts.check_interval,
        confidence_threshold: opts.confidence_threshold
      },
      last_check: DateTime.utc_now()
    }

    schedule_check(state.config.check_interval)
    {:ok, state}
  end

  @impl true
  def deliver_signal(state) do
    metrics = analyze_quality_since(state.last_check)

    signal_type = determine_signal_type(metrics, state.config)

    {:ok, Jido.Signal.new(%{
      source: "#{state.sensor.name}:#{state.id}",
      type: signal_type,
      data: metrics
    })}
  end

  @impl true
  def handle_info(:check, state) do
    # Trigger signal delivery
    {:noreply, %{state | last_check: DateTime.utc_now()}}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp analyze_quality_since(_timestamp) do
    # Placeholder - would query actual review data
    %{
      avg_confidence: 0.82,
      review_count: 15,
      escalation_rate: 0.13,
      pattern_learning_rate: 0.65
    }
  end

  defp determine_signal_type(metrics, config) do
    cond do
      metrics.avg_confidence < config.confidence_threshold ->
        "review.quality.alert"

      metrics.pattern_learning_rate > 0.8 ->
        "review.learning.success"

      true ->
        "review.quality.report"
    end
  end
end
```

**Steps 3-4:** Refactor and verify as above

---

## Phase 3: Architecture (Low Priority)

### LP-1: Signal-Based Architecture

**This is a major architectural change - detailed implementation in separate spike document**

#### Prerequisites
- Phase 1 complete
- Phase 2 complete
- Architectural spike approved

#### High-Level Steps

1. **Convert agents to GenServers**
   - Add start_link/1 to CriticAgent
   - Implement Jido.Agent.Server pattern
   - Add supervision tree

2. **Define signal routing**
   - Create route definitions
   - Implement handle_signal callbacks
   - Add signal emission logic

3. **Update orchestrator**
   - Change from function calls to signal emission
   - Add signal correlation logic
   - Implement response aggregation

4. **Comprehensive testing**
   - Test signal routing
   - Test async processing
   - Test error scenarios
   - Test signal correlation

**Effort:** High (8-10 hours)
**Risk:** Moderate
**Recommendation:** Implement as spike first, evaluate value

---

## Testing Requirements

### Test Coverage Targets

**Phase 1:**
- Maintain 100% of existing test coverage
- Add chain execution tests (5+ new tests)
- Add compensation tests (3+ new tests)
- Agent DSL migration (convert ~10 tests)

**Phase 2:**
- Sensor tests (5+ new tests)
- Async execution tests (3+ new tests)
- Integration tests for monitoring

**Phase 3:**
- Signal routing tests (10+ new tests)
- GenServer lifecycle tests (5+ new tests)
- Async communication tests (5+ new tests)

### Test Principles

1. **Write tests first** - No implementation without failing test
2. **Test behavior, not implementation** - Focus on outcomes
3. **Isolate tests** - Each test independent
4. **Use descriptive names** - Tests as documentation
5. **Assert on important details** - Not every field

---

## Documentation Requirements

### Per Enhancement

Each implementation must include:

1. **Module documentation**
   - @moduledoc with overview
   - @doc for public functions
   - Examples in docs

2. **Change documentation**
   - Update relevant guides
   - Add migration notes if needed
   - Update architecture diagrams

3. **Test documentation**
   - Test descriptions
   - Setup explanations
   - Edge case documentation

---

## Rollback Plan

### Phase 1 Rollback

**If Chain.chain doesn't work well:**
```elixir
# Keep old ReviewOrchestrator
# Use feature flag to toggle
@use_chain Application.compile_env(:synapse, :use_chain_orchestrator, false)

def evaluate(input) do
  if @use_chain do
    ChainOrchestrator.evaluate(input)
  else
    ReviewOrchestrator.evaluate(input)
  end
end
```

**If compensation causes issues:**
- Disable compensation: `compensation: [enabled: false]`
- Remove on_error/4 callback
- Tests still pass (compensation is optional)

**If AgentCase migration problematic:**
- Keep both test styles
- No need to migrate all at once
- Can use helpers selectively

---

## Success Metrics

### Phase 1 Metrics

- ✅ Chain.chain handles 100% of workflow executions
- ✅ 50%+ of agent tests use AgentCase helpers
- ✅ LLM action has working compensation
- ✅ All 60+ tests passing
- ✅ No performance regression (< 5% slower acceptable)
- ✅ Test execution time < 2 seconds

### Phase 2 Metrics

- ✅ Quality sensor running and emitting signals
- ✅ Async LLM execution working
- ✅ Per-action timeout configuration used
- ✅ All 70+ tests passing
- ✅ Latency reduced by 20%+ for parallel workflows

### Phase 3 Metrics

- ✅ Signal-based architecture operational
- ✅ Agents running as supervised GenServers
- ✅ Event audit trail complete
- ✅ All 85+ tests passing
- ✅ Can handle 10x concurrent review requests

---

## Agent Instructions (Execute Each Session)

### Session Workflow

1. **READ** all required reading documents (refresh context)

2. **IDENTIFY** current phase and next task:
   - Check implementation status below
   - Select next uncompleted task
   - Read relevant design section

3. **PLAN** implementation:
   - Identify test files needed
   - Identify implementation files needed
   - List required dependencies/imports
   - Estimate time/complexity

4. **IMPLEMENT** using TDD:
   - RED: Write failing test
   - GREEN: Minimal implementation
   - REFACTOR: Clean up code
   - VERIFY: Full test suite

5. **UPDATE** this prompt:
   - Mark task as complete
   - Add implementation notes
   - Document decisions made
   - Note any blockers

6. **REPORT** progress:
   - Summarize what was completed
   - Note any issues encountered
   - Recommend next steps

---

## Implementation Status Checklist

### Phase 1: Foundation (High Priority)

- [ ] **HP-1: Chain.chain workflows**
  - [ ] Write failing ChainOrchestrator tests
  - [ ] Implement ChainOrchestrator module
  - [ ] Extract chain building helpers
  - [ ] Update ReviewOrchestrator deprecation notice
  - [ ] Verify all tests pass
  - [ ] Update workflow documentation

- [ ] **HP-2: JidoTest.AgentCase**
  - [ ] Create example test with full DSL
  - [ ] Migrate simple_executor_test.exs
  - [ ] Migrate critic_agent_test.exs
  - [ ] Migrate workflow tests
  - [ ] Document DSL patterns
  - [ ] Verify all tests pass

- [ ] **HP-3: LLM compensation**
  - [ ] Write compensation tests
  - [ ] Add compensation config to action
  - [ ] Implement on_error/4 callback
  - [ ] Add request tracking
  - [ ] Add cleanup logic
  - [ ] Verify compensation works

### Phase 2: Monitoring (Medium Priority)

- [ ] **MP-2: Quality sensor**
  - [ ] Write sensor tests
  - [ ] Implement ReviewQualityMonitor
  - [ ] Add metric analysis logic
  - [ ] Integrate with existing agents
  - [ ] Add monitoring dashboard (optional)

- [ ] **MP-1: Async execution**
  - [ ] Write async workflow tests
  - [ ] Implement run_async variant
  - [ ] Add await/cancel logic
  - [ ] Test timeout handling
  - [ ] Verify performance improvement

- [ ] **MP-3: Instruction config**
  - [ ] Update tests to use Instructions
  - [ ] Refactor workflows to use Instructions
  - [ ] Add per-action config
  - [ ] Verify config applied correctly

### Phase 3: Architecture (Low Priority)

- [ ] **LP-1: Signal architecture**
  - [ ] Write spike implementation
  - [ ] Evaluate architectural fit
  - [ ] If approved, full implementation
  - [ ] Migration guide
  - [ ] Parallel operation with old code

- [ ] **LP-2: Skills**
  - [ ] Define CodeReview skill
  - [ ] Implement skill router
  - [ ] Update agents to use skills
  - [ ] Migrate action registration

- [ ] **LP-3: Cron sensors**
  - [ ] Define periodic analysis jobs
  - [ ] Implement analysis logic
  - [ ] Add reporting signals
  - [ ] Integrate with monitoring

- [ ] **LP-4: Directives**
  - [ ] Update actions to return directives
  - [ ] Test directive handling
  - [ ] Verify dynamic workflows
  - [ ] Document directive patterns

---

## Notes & Decisions

### Session Log

**Format:** `YYYY-MM-DD: Brief note about progress/decisions`

- `2025-10-28`: Prompt created, ready for Phase 1 implementation

---

## Troubleshooting Guide

### Common Issues

**Issue: AgentCase DSL doesn't work with stateless agents**
- **Solution:** Use helper functions only, not full pipeline DSL
- **Or:** Convert agents to GenServer pattern (Phase 3)

**Issue: Chain.chain changes result structure**
- **Solution:** Add format_chain_results/2 adapter function
- **Keep:** Existing API surface unchanged

**Issue: Compensation not triggering**
- **Solution:** Verify `compensation: [enabled: true]` in action config
- **Check:** Error is actually raised, not silently handled

**Issue: Sensor signals not received**
- **Solution:** Verify target configuration
- **Check:** Sensor process is alive
- **Debug:** Add logging to deliver_signal/1

---

## Additional Resources

### Jido Documentation Links

- [Actions Guide](https://hexdocs.pm/jido/Jido.Action.html)
- [Agents Guide](https://hexdocs.pm/jido/Jido.Agent.html)
- [Workflow Guide](https://hexdocs.pm/jido/Jido.Workflow.html)
- [Testing Guide](https://hexdocs.pm/jido/testing.html)

### Example Implementations

- [Jido Workbench](https://github.com/agentjido/jido_workbench) - Example agents
- Test files in jido package for patterns

---

## Conclusion

This prompt provides complete guidance for implementing Jido enhancements using TDD. Begin with Phase 1, assess value, and proceed incrementally. Update this document as you progress to maintain institutional knowledge.

**Next Action:** Begin HP-1 implementation by reading required documents and writing first failing test.
