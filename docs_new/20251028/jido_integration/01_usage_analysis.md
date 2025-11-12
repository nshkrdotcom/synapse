# Synapse Jido Framework Usage Analysis

**Date:** 2025-10-28
**Scope:** Comprehensive analysis of Jido framework adoption in Synapse codebase
**Status:** Current state assessment

---

## Executive Summary

Synapse demonstrates **foundational usage of Jido** (40% feature adoption) with strong implementation of core primitives (Actions, Agents, Error handling) but operates in a **stateless, functional style** rather than Jido's event-driven, signal-based architecture. The codebase focuses on multi-agent orchestration for code review automation with LLM integration.

**Adoption Metrics:**
- **Features Used:** 5/12 (42%)
- **Maturity Level:** Foundational (Actions, Agents, Exec)
- **Architecture Style:** Stateless functional (vs. event-driven)
- **Test Coverage:** Basic ExUnit (no JidoTest helpers)

---

## Detailed Feature Analysis

### 1. Actions - ✅ BASIC USAGE

**Implementation Status:** Active in 3 modules

#### Files Using Jido.Action

**1.1 Echo Action** (`lib/synapse/actions/echo.ex`)
```elixir
use Jido.Action,
  name: "echo",
  description: "Echoes a message back",
  schema: [
    message: [type: :string, required: true, doc: "The message to echo"]
  ]

def run(%{message: message}, _context) do
  {:ok, %{message: message}}
end
```

**Features used:**
- ✅ Basic schema validation with NimbleOptions
- ✅ Simple run/2 implementation
- ✅ Standard {:ok, result} return pattern

**Features NOT used:**
- ❌ `on_error/4` compensation callback
- ❌ `compensation: [enabled: true]` configuration
- ❌ Action metadata (category, tags)
- ❌ Advanced schema features (custom types, nested validation)

---

**1.2 CriticReview Action** (`lib/synapse/actions/critic_review.ex`)
```elixir
use Jido.Action,
  name: "critic_review",
  description: "Reviews code and provides confidence assessment",
  schema: [
    code: [type: :string, required: true],
    intent: [type: :string, required: true],
    constraints: [type: {:list, :string}, default: []]
  ]

def run(params, _context) do
  issues = detect_issues(params)
  confidence = calculate_confidence(params, issues)

  {:ok, %{
    confidence: confidence,
    issues: issues,
    recommendations: generate_recommendations(issues),
    should_escalate: confidence < 0.7,
    reviewed_at: DateTime.utc_now()
  }}
end
```

**Features used:**
- ✅ Multi-parameter schema with defaults
- ✅ Business logic in run/2
- ✅ Structured result output

**Features NOT used:**
- ❌ Error handling callbacks
- ❌ Context usage for shared data
- ❌ Telemetry emission
- ❌ Timeout configuration

---

**1.3 GenerateCritique Action** (`lib/synapse/actions/generate_critique.ex`)
```elixir
use Jido.Action,
  name: "generate_critique",
  description: "Uses an LLM (via Req) to produce review suggestions",
  schema: [
    prompt: [type: :string, required: true],
    messages: [type: {:list, :map}, default: []],
    temperature: [type: {:or, [:float, nil]}, default: nil],
    max_tokens: [type: {:or, [:integer, nil]}, default: nil],
    profile: [type: {:or, [:atom, :string]}, default: nil]
  ]

def run(params, _context) do
  llm_params = Map.take(params, [:prompt, :messages, :temperature, :max_tokens])
  profile = Map.get(params, :profile)

  case ReqLLM.chat_completion(llm_params, profile: profile) do
    {:ok, response} -> {:ok, response}
    {:error, %Error{} = error} -> {:error, error}
    {:error, other} -> {:error, Error.execution_error("LLM request failed", %{reason: other})}
  end
end
```

**Features used:**
- ✅ Advanced schema with optional types
- ✅ Jido.Error integration
- ✅ External service integration pattern

**Features NOT used:**
- ❌ Async execution for long LLM requests
- ❌ Retry configuration (relies on ReqLLM instead)
- ❌ Compensation on LLM failure
- ❌ Telemetry for LLM metrics

---

#### Action Usage Summary

| Feature | Status | Adoption |
|---------|--------|----------|
| Schema validation | ✅ Used | 3/3 actions |
| run/2 implementation | ✅ Used | 3/3 actions |
| Error tuples | ✅ Used | 3/3 actions |
| Jido.Error integration | ✅ Used | 1/3 actions |
| on_error/4 callbacks | ❌ Not used | 0/3 actions |
| Compensation | ❌ Not used | 0/3 actions |
| Async execution | ❌ Not used | 0/3 actions |
| Metadata (category/tags) | ❌ Not used | 0/3 actions |
| Directives | ❌ Not used | 0/3 actions |

**Adoption Rate:** 4/9 features = 44%

---

### 2. Agents - ✅ STATEFUL PATTERN (Stateless Structs)

**Implementation Status:** Active in 2 modules

#### 2.1 SimpleExecutor Agent

**File:** `lib/synapse/agents/simple_executor.ex`

```elixir
use Jido.Agent,
  name: "simple_executor",
  description: "Executes actions and tracks execution count",
  actions: [Synapse.Actions.Echo],
  schema: [
    execution_count: [type: :integer, default: 0, doc: "Number of executions"]
  ]
```

**State Management:**
- Single integer counter
- Updated via `on_after_run/3` callback
- Maintains execution history

**Lifecycle Callbacks Implemented:**
```elixir
def on_before_run(agent) do
  require Logger
  Logger.info("SimpleExecutor preparing to run")
  {:ok, agent}
end

def on_after_run(agent, _result, _directives) do
  Jido.Agent.set(agent, %{execution_count: agent.state.execution_count + 1})
end
```

**Usage Pattern:**
```elixir
# Stateless struct operation
agent = SimpleExecutor.new()
{:ok, agent, _directives} = SimpleExecutor.cmd(agent, {Echo, %{message: "test"}})
# Returns new agent instance
```

**Features used:**
- ✅ Schema-based state validation
- ✅ Lifecycle callbacks (on_before_run, on_after_run)
- ✅ Action registration
- ✅ Immutable state updates via Jido.Agent.set/2

**Features NOT used:**
- ❌ Jido.Agent.Server GenServer pattern
- ❌ start_link/1 for supervised processes
- ❌ Signal-based communication
- ❌ handle_signal/1 callback
- ❌ Sensors or Skills
- ❌ Signal routing

---

#### 2.2 CriticAgent

**File:** `lib/synapse/agents/critic_agent.ex`

```elixir
use Jido.Agent,
  name: "critic",
  description: "Reviews code and learns from feedback",
  actions: [Synapse.Actions.CriticReview],
  schema: [
    review_count: [type: :integer, default: 0],
    review_history: [type: {:list, :map}, default: []],
    learned_patterns: [type: {:list, :map}, default: []],
    decision_fossils: [type: {:list, :map}, default: []],
    scar_tissue: [type: {:list, :map}, default: []]
  ]
```

**Sophisticated State Tracking:**

1. **review_count** - Simple counter
2. **review_history** - Circular buffer (max 100 items)
3. **learned_patterns** - Knowledge accumulation
4. **decision_fossils** - Planning context snapshots (max 50)
5. **scar_tissue** - Failure records for learning (max 50)

**State Management Logic:**
```elixir
def on_after_run(agent, _result, _directives) do
  review = %{
    confidence: agent.result.confidence,
    escalated: agent.result.should_escalate,
    summary: summarize_review(agent.result),
    timestamp: DateTime.utc_now()
  }

  updated_state = agent.state
    |> Map.update!(:review_count, &(&1 + 1))
    |> Map.update!(:review_history, &maintain_circular_buffer(&1, review, 100))
    |> Map.update!(:decision_fossils, &maintain_circular_buffer(&1, extract_fossil(review), 50))

  Jido.Agent.set(agent, updated_state)
end
```

**Custom Methods:**
```elixir
def record_failure(agent, failure_info) do
  Jido.Agent.set(agent, %{
    scar_tissue: [failure_info | agent.state.scar_tissue] |> Enum.take(50)
  })
end

def learn_from_correction(agent, correction) do
  pattern = extract_pattern(correction)
  Jido.Agent.set(agent, %{
    learned_patterns: [pattern | agent.state.learned_patterns]
  })
end
```

**Features used:**
- ✅ Complex state schema (5 fields)
- ✅ Lifecycle callbacks (on_after_run)
- ✅ Circular buffer implementation
- ✅ Custom state management methods
- ✅ Learning/adaptation pattern

**Features NOT used:**
- ❌ GenServer pattern (not a supervised process)
- ❌ Signal handling
- ❌ Sensors for periodic reviews
- ❌ Skills for capability bundling
- ❌ Inter-agent signaling

---

#### Agent Usage Summary

| Feature | SimpleExecutor | CriticAgent | Adoption |
|---------|----------------|-------------|----------|
| Schema validation | ✅ | ✅ | 2/2 |
| Lifecycle callbacks | ✅ | ✅ | 2/2 |
| Action registration | ✅ | ✅ | 2/2 |
| Stateless structs | ✅ | ✅ | 2/2 |
| Agent.Server (GenServer) | ❌ | ❌ | 0/2 |
| start_link/1 | ❌ | ❌ | 0/2 |
| Signal handling | ❌ | ❌ | 0/2 |
| Sensors | ❌ | ❌ | 0/2 |
| Skills | ❌ | ❌ | 0/2 |

**Adoption Rate:** 5/10 features = 50%

---

### 3. Jido.Exec - ✅ SINGLE ACTION EXECUTION

**Usage Location:** `lib/synapse/workflows/review_orchestrator.ex:59-71`

```elixir
def request_llm_suggestion(message, reviewer_feedback, profile) do
  feedback_json = Jason.encode!(reviewer_feedback)

  prompt = """
  Provide concrete next steps to strengthen the submission.

  Code: #{message}
  Critic feedback: #{feedback_json}
  """

  Jido.Exec.run(
    GenerateCritique,
    %{
      prompt: prompt,
      messages: [%{role: "system", content: "You are assisting a software engineer"}],
      profile: profile
    }
  )
end
```

**Features used:**
- ✅ Direct action execution
- ✅ Parameter passing
- ✅ Error propagation

**Features NOT used:**
- ❌ Timeout configuration: `Jido.Exec.run(Action, params, context, timeout: 10_000)`
- ❌ Retry options: `max_retries: 3, backoff: 250`
- ❌ Telemetry configuration: `telemetry: :full`
- ❌ Context passing for shared state

---

### 4. Jido.Error - ✅ COMPREHENSIVE USAGE

**Strong Adoption Across 6 Modules**

#### Error Types Used

**Config Errors:**
```elixir
Error.config_error("Synapse.ReqLLM configuration is missing")
Error.config_error("Unknown LLM profile #{inspect(profile)}")
Error.config_error("Model #{inspect(model)} is not allowed")
```

**Execution Errors:**
```elixir
Error.execution_error("LLM request failed", %{
  profile: profile_name,
  status: status,
  body: sanitized_body,
  provider: :openai
})
```

#### Files Using Jido.Error

1. **lib/synapse/req_llm.ex** - Configuration and HTTP errors
2. **lib/synapse/providers/openai.ex** - Provider-specific errors
3. **lib/synapse/providers/gemini.ex** - Provider-specific errors
4. **lib/synapse/actions/generate_critique.ex** - Action execution errors
5. **lib/mix/tasks/synapse.demo.ex** - CLI error handling
6. **test/** - Error assertions in tests

**Error Propagation Pattern:**
```elixir
# Consistent error handling across all modules
case operation() do
  {:ok, result} -> {:ok, result}
  {:error, %Jido.Error{} = error} -> {:error, error}
  {:error, other} -> {:error, Error.execution_error("Operation failed", %{reason: other})}
end
```

**Adoption Rate:** 100% - All error handling goes through Jido.Error

---

### 5. Workflows - ⚠️ PARTIAL/MANUAL USAGE

**Implementation:** Manual orchestration in `lib/synapse/workflows/review_orchestrator.ex`

**Current Pattern:**
```elixir
def evaluate(%{message: message, intent: intent} = input) do
  constraints = Map.get(input, :constraints, [])
  profile = Map.get(input, :llm_profile)

  with {:ok, executor_agent, _} <-
         SimpleExecutor.new()
         |> SimpleExecutor.cmd({Echo, %{message: message}}),
       executor_output <- executor_agent.result,
       {:ok, critic_agent, _} <-
         CriticAgent.new()
         |> CriticAgent.cmd({CriticReview, %{code: message, intent: intent, constraints: constraints}}),
       reviewer_feedback <- critic_agent.result,
       {:ok, suggestion} <- request_llm_suggestion(message, reviewer_feedback, profile) do
    {:ok, %{
      executor_output: executor_output,
      review: reviewer_feedback,
      suggestion: suggestion,
      audit_trail: %{
        review_count: critic_agent.state.review_count,
        decision_fossils: critic_agent.state.decision_fossils
      }
    }}
  end
end
```

**What's being done:**
- ✅ Multi-step orchestration (executor → critic → LLM)
- ✅ Result accumulation
- ✅ Error propagation via with construct

**What's NOT being used:**
- ❌ `Jido.Workflow.Chain.chain/3` for declarative pipelines
- ❌ Formal Jido.Workflow module
- ❌ Instruction structs
- ❌ Automatic retry/compensation
- ❌ Per-step timeout configuration

**Available Alternative:**
```elixir
# Could use Chain.chain instead
{:ok, result} = Jido.Workflow.Chain.chain(
  [
    {Echo, []},
    {CriticReview, []},
    {GenerateCritique, [timeout: 30_000]}
  ],
  %{message: message, intent: intent},
  context: %{profile: profile}
)
```

---

### 6. Features NOT Used

#### 6.1 Signals - ❌ NOT IMPLEMENTED

**What's available in Jido:**
```elixir
# CloudEvents-compatible signals
signal = Jido.Signal.new!(%{
  type: "review.request",
  source: "/reviews/critic",
  data: %{code: code, intent: intent}
})

# Async agent communication
CriticAgent.cast(agent_pid, signal)

# Signal routing
routes: [
  {"review.request", %Instruction{action: CriticReview}},
  {"review.complete", %Instruction{action: GenerateCritique}}
]
```

**Use cases in Synapse:**
- Could enable event-driven review workflows
- Async communication between executor and critic
- Audit trail via signal chains
- Pattern-based routing for different review types

**Current gap:** All communication is synchronous function calls

---

#### 6.2 Sensors - ❌ NOT IMPLEMENTED

**What's available in Jido:**
```elixir
# Monitor review quality
defmodule Synapse.Sensors.QualityMonitor do
  use Jido.Sensor,
    name: "quality_monitor",
    schema: [
      check_interval: [type: :pos_integer, default: 60_000]
    ]

  def deliver_signal(state) do
    metrics = analyze_recent_reviews()

    {:ok, Jido.Signal.new(%{
      type: "quality.report",
      data: metrics
    })}
  end
end

# Periodic pattern detection
{:ok, _} = Jido.Sensors.Cron.start_link(
  jobs: [{~e"0 * * * *"e, :hourly_pattern_analysis}]
)
```

**Use cases in Synapse:**
- Monitor review quality over time
- Detect learning patterns
- Track confidence score trends
- Automated metric collection
- Health monitoring for agents

**Current gap:** No automated monitoring or event detection

---

#### 6.3 Skills - ❌ NOT IMPLEMENTED

**What's available in Jido:**
```elixir
# Bundle review capabilities
defmodule Synapse.Skills.CodeReview do
  use Jido.Skill,
    name: "code_review",
    description: "Comprehensive code review capabilities",
    actions: [
      Synapse.Actions.CriticReview,
      Synapse.Actions.GenerateCritique,
      Synapse.Actions.FormatCode
    ],
    signals: [
      input: ["review.request.*"],
      output: ["review.complete.*"]
    ]
end

# Agent uses skill
use Jido.Agent,
  skills: [Synapse.Skills.CodeReview]
```

**Benefits for Synapse:**
- Package related review actions
- Reusable review capability
- Plugin architecture for review strategies
- Automatic action registration

**Current gap:** Actions registered directly, no capability bundling

---

#### 6.4 Instructions - ❌ NOT IMPLEMENTED

**What's available in Jido:**
```elixir
# Declarative workflow with per-action config
instructions = [
  %Instruction{
    action: CriticReview,
    params: %{code: code, intent: intent},
    opts: [timeout: 10_000]
  },
  %Instruction{
    action: GenerateCritique,
    params: %{prompt: prompt},
    opts: [timeout: 30_000, retry: true]
  }
]

{:ok, agent, _} = CriticAgent.cmd(agent, instructions)
```

**Benefits for Synapse:**
- Per-action timeout configuration
- Individual retry policies
- Declarative composition
- Better error isolation

**Current pattern:** Tuple format `{Action, params}` without options

---

#### 6.5 Directives - ❌ NOT IMPLEMENTED

**What's available in Jido:**
```elixir
# Actions can modify agent behavior
def run(params, _context) do
  directive = %Jido.Agent.Directive.Enqueue{
    action: :follow_up_review,
    params: %{review_id: params.review_id}
  }

  {:ok, %{review_complete: true}, directive}
end
```

**Use cases in Synapse:**
- CriticReview could queue follow-up actions based on confidence
- GenerateCritique could spawn additional critique iterations
- Dynamic workflow adaptation

**Current gap:** No self-modifying workflows

---

#### 6.6 Agent.Server (GenServer Pattern) - ❌ NOT IMPLEMENTED

**What's available in Jido:**
```elixir
defmodule Synapse.Agents.CriticAgent do
  use Jido.Agent, name: "critic"

  # Enable supervised process
  def start_link(opts) do
    Jido.Agent.Server.start_link(
      id: opts[:id],
      agent: __MODULE__,
      mode: :auto,
      routes: [
        {"review.request", %Instruction{action: CriticReview}}
      ]
    )
  end

  # Signal handling
  def handle_signal(%Signal{type: "review.request"} = signal) do
    {:ok, signal}
  end
end

# Start under supervision
children = [
  {Synapse.Agents.CriticAgent, id: "critic_1"}
]
Supervisor.start_link(children, strategy: :one_for_one)

# Async communication
CriticAgent.cast("critic_1", review_signal)
```

**Benefits:**
- Long-lived reviewer processes
- Background review processing
- Concurrent review handling
- Fault tolerance via supervision

**Current pattern:** Agents created as ephemeral structs per request

---

### 7. Testing - ⚠️ BASIC EXUNIT ONLY

**Current Testing Pattern:**

```elixir
# lib/synapse/actions/echo_test.exs
test "echoes message" do
  {:ok, result} = Echo.run(%{message: "test"}, %{})
  assert result.message == "test"
end

# lib/synapse/agents/critic_agent_test.exs
test "stores decision fossils" do
  agent = CriticAgent.new()
  {:ok, agent, _} = CriticAgent.cmd(agent, {CriticReview, %{...}})
  assert agent.state.review_count == 1
end
```

**What's NOT being used:**
```elixir
# JidoTest.AgentCase DSL
use JidoTest.AgentCase

spawn_agent(CriticAgent)
|> assert_agent_state(review_count: 0)
|> send_signal_sync("review.request", %{code: code})
|> assert_agent_state(review_count: 1)
|> assert_queue_empty()
```

**Missing test features:**
- AgentCase DSL helpers
- Signal testing utilities
- Queue management assertions
- Async test patterns
- Property-based testing with StreamData

---

## Architecture Comparison

### Current: Stateless Functional Style

```
User Request
    ↓
ReviewOrchestrator
    ↓
┌─────────────────┐
│ SimpleExecutor  │ ← Created per request
│   (new/cmd)     │ ← Stateless struct
└─────────────────┘
    ↓
┌─────────────────┐
│ CriticAgent     │ ← Created per request
│   (new/cmd)     │ ← Stateless struct
└─────────────────┘
    ↓
┌─────────────────┐
│ GenerateCritique│ ← Jido.Exec.run
│   (LLM call)    │
└─────────────────┘
    ↓
Response
```

**Characteristics:**
- Synchronous execution
- Function call communication
- Ephemeral agents
- Manual orchestration
- No event bus

---

### Potential: Event-Driven Signal Style

```
User Request
    ↓
Signal: "review.request"
    ↓
Signal Bus (Phoenix.PubSub)
    ↓
┌─────────────────────────────┐
│ CriticAgent (GenServer)     │ ← Long-lived supervised process
│   - routes: review.request  │ ← Signal routing
│   - sensors: QualityMonitor │ ← Background monitoring
│   - skills: CodeReview      │ ← Capability bundle
└─────────────────────────────┘
    ↓ (emits signal)
Signal: "review.complete"
    ↓
┌─────────────────────────────┐
│ LLMAgent (GenServer)        │ ← Dedicated LLM processor
│   - routes: review.complete │
│   - retry: exponential      │
└─────────────────────────────┘
    ↓ (emits signal)
Signal: "critique.ready"
    ↓
Response
```

**Benefits:**
- Async execution
- Decoupled components
- Event audit trail
- Background monitoring
- Horizontal scalability

---

## Code Statistics

### Lines of Code by Category

| Category | Files | Total Lines | Using Jido |
|----------|-------|-------------|------------|
| Actions | 3 | ~170 | 100% |
| Agents | 2 | ~180 | 100% |
| Workflows | 1 | ~75 | Partial (Exec only) |
| Providers | 2 | ~650 | 0% (custom) |
| ReqLLM | 1 | ~550 | Error only |
| Tests | 11 | ~900 | Minimal |

### Jido API Surface Usage

| API Module | Methods Used | Methods Available | Usage % |
|------------|--------------|-------------------|---------|
| Jido.Action | use, run/2 | +on_error, +async | 30% |
| Jido.Agent | use, new, cmd, set | +Server, +Signals | 40% |
| Jido.Exec | run/3 | +async, +options | 25% |
| Jido.Error | config/execution | Full | 100% |
| Jido.Workflow | - | Chain, Instructions | 0% |
| Jido.Signal | - | new, routing | 0% |
| Jido.Sensor | - | Cron, Heartbeat | 0% |
| Jido.Skill | - | Bundles, registration | 0% |

---

## Gap Analysis

### Critical Gaps (Impacting Current Functionality)

None - current implementation is functional and complete for its use case.

### Enhancement Opportunities (Would Add Value)

**1. Workflow Formalization**
- **Current:** Manual with constructs
- **Available:** Jido.Workflow.Chain.chain
- **Benefit:** Automatic error propagation, retry logic, cleaner composition

**2. Async LLM Processing**
- **Current:** Synchronous LLM calls block workflow
- **Available:** Jido.Workflow.run_async
- **Benefit:** Better responsiveness, parallel reviews

**3. Review Quality Monitoring**
- **Current:** No automated monitoring
- **Available:** Jido.Sensors with periodic checks
- **Benefit:** Proactive quality detection, trend analysis

### Architectural Gaps (Different Design Choice)

**1. Stateless vs Stateful Agents**
- **Current:** Ephemeral agent structs per request
- **Available:** Long-lived GenServer agents
- **Trade-off:** Simplicity vs. persistent state/background processing

**2. Functional vs Event-Driven**
- **Current:** Function calls for orchestration
- **Available:** Signal-based async communication
- **Trade-off:** Simplicity vs. scalability/decoupling

---

## Recommendations

### Keep Current Approach For:

1. **Stateless agents** - Simpler to test and reason about
2. **Jido.Error** - Excellent standardization
3. **Action schemas** - Good validation foundation

### Consider Adopting:

1. **Chain.chain** - Better workflow composition (High Priority)
2. **JidoTest helpers** - Cleaner test syntax (Medium Priority)
3. **Sensors** - Automated monitoring (Low Priority)

### Don't Need:

1. **Signals** - Synchronous flow is simpler for this use case
2. **Skills** - Only 3 actions, no need for bundling yet
3. **Agent.Server** - Stateless pattern works well currently

---

## Conclusion

Synapse demonstrates **smart, focused adoption** of Jido's core primitives while avoiding complexity that doesn't add value to the current use case. The architecture choice (stateless, functional) is **appropriate for a code review automation tool** where:

- Requests are one-off operations
- State doesn't persist between reviews
- Synchronous execution is acceptable
- Simplicity aids debugging

**Framework Adoption:** 40% (foundational features)
**Architecture Fit:** Excellent
**Recommended Evolution:** Incremental (Chain → Testing → Sensors)

**Key Strength:** The team **avoided over-engineering** by not adopting features that would add complexity without commensurate value.
