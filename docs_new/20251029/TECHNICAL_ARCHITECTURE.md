# Synapse Technical Architecture
**Version**: 2.0
**Date**: October 29, 2025
**Status**: Stage 2 Complete + LLM Integration

---

## System Overview

Synapse is a **signal-driven multi-agent code review system** built on the BEAM VM using Elixir and the Jido agent framework. The architecture emphasizes:

- **Autonomy**: Agents operate independently via signal subscriptions
- **Scalability**: Lightweight BEAM processes enable massive concurrency
- **Observability**: CloudEvents-compliant signals provide full audit trails
- **Extensibility**: Plugin architecture for agents, actions, and LLM providers

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Synapse Application                          │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Supervision Tree                           │ │
│  │                                                              │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │ Jido.Signal  │  │    Agent     │  │  Orchestrator   │  │ │
│  │  │     .Bus     │  │  Registry    │  │    Runtime      │  │ │
│  │  │(:synapse_bus)│  │(:synapse_    │  │   (optional)    │  │ │
│  │  │              │  │  registry)   │  │                 │  │ │
│  │  └──────┬───────┘  └───────┬──────┘  └────────┬────────┘  │ │
│  │         │                  │                    │           │ │
│  └─────────┼──────────────────┼────────────────────┼───────────┘ │
│            │                  │                    │             │
│            │                  │                    │             │
│  ┌─────────▼──────────────────▼────────────────────▼───────────┐ │
│  │                     Agent Layer                              │ │
│  │                                                               │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────┐  │ │
│  │  │  Coordinator    │  │    Security     │  │Performance │  │ │
│  │  │ AgentServer     │  │  AgentServer    │  │AgentServer │  │ │
│  │  │                 │  │                 │  │            │  │ │
│  │  │ • Classifies    │  │ • SQL Injection │  │• Complexity│  │ │
│  │  │ • Spawns        │  │ • XSS           │  │• Memory    │  │ │
│  │  │ • Aggregates    │  │ • Auth Issues   │  │• Hot Paths │  │ │
│  │  └─────────────────┘  └─────────────────┘  └────────────┘  │ │
│  └───────────────────────────────────────────────────────────── │ │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     Action Layer                           │  │
│  │                                                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │  │
│  │  │   Review    │  │  Security   │  │   Performance    │  │  │
│  │  │   Actions   │  │   Actions   │  │     Actions      │  │  │
│  │  │             │  │             │  │                  │  │  │
│  │  │• Classify   │  │• CheckSQL   │  │• CheckComplexity│  │  │
│  │  │• Summarize  │  │• CheckXSS   │  │• CheckMemory    │  │  │
│  │  │             │  │• CheckAuth  │  │• ProfileHotPath │  │  │
│  │  └─────────────┘  └─────────────┘  └──────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     LLM Layer                              │  │
│  │                                                             │  │
│  │  ┌──────────────┐      ┌──────────────┐                  │  │
│  │  │   ReqLLM     │─────▶│   Providers  │                  │  │
│  │  │   Client     │      │              │                  │  │
│  │  │              │      │ • OpenAI     │                  │  │
│  │  │• Multi-      │      │ • Gemini     │                  │  │
│  │  │  profile     │      │ • (future)   │                  │  │
│  │  │• Retry logic │      └──────────────┘                  │  │
│  │  │• Telemetry   │                                         │  │
│  │  └──────────────┘                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Signal Bus (Jido.Signal.Bus)

**Purpose**: CloudEvents-compliant pub/sub message router

**Implementation**:
```elixir
# Started in Application supervision tree
{Jido.Signal.Bus, name: :synapse_bus}
```

**Features**:
- Pattern-based subscription (e.g., `"review.*"`)
- Async message delivery
- Multiple dispatch adapters (PID, PubSub, HTTP, Logger)
- Signal history and replay
- Correlation via `subject` field

**Signal Types**:
```elixir
# Request: Start a review
%Signal{
  type: "review.request",
  source: "/synapse/api",
  subject: "jido://review/#{review_id}",
  data: %{
    review_id: "r123",
    diff: "...",
    files_changed: 50,
    labels: ["security"],
    metadata: %{...}
  }
}

# Result: Specialist finding
%Signal{
  type: "review.result",
  source: "/synapse/agents/security_specialist",
  subject: "jido://review/#{review_id}",
  data: %{
    review_id: "r123",
    agent: "security_specialist",
    findings: [...],
    confidence: 0.85
  }
}

# Summary: Final aggregated result
%Signal{
  type: "review.summary",
  source: "/synapse/agents/coordinator",
  subject: "jido://review/#{review_id}",
  data: %{
    review_id: "r123",
    status: :complete,
    severity: :high,
    findings: [...],
    recommendations: [...]
  }
}
```

---

### 2. Agent Registry

**Purpose**: Track and manage agent processes

**Implementation**: Custom GenServer

```elixir
defmodule Synapse.AgentRegistry do
  use GenServer

  # State: %{agent_id => pid}

  def get_or_spawn(registry, agent_id, module, opts) do
    case lookup(registry, agent_id) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :not_found} ->
        {:ok, pid} = start_agent(module, opts)
        register(registry, agent_id, pid)
        {:ok, pid}
    end
  end
end
```

**Features**:
- Idempotent agent spawning
- Process lifecycle tracking
- Automatic cleanup on process death
- Supports both GenServer and stateless agents

**Location**: `lib/synapse/agent_registry.ex` (217 lines)

---

### 3. Agent Layer

#### CoordinatorAgentServer

**Responsibility**: Orchestration hub

**Lifecycle**:
1. Subscribe to `review.request` and `review.result` signals
2. On request: Classify change (fast_path vs deep_review)
3. If deep_review: Spawn specialists via AgentRegistry
4. Track pending specialists in `active_reviews` state
5. On result: Aggregate findings
6. When complete: Emit `review.summary`

**State**:
```elixir
%{
  agent: %CoordinatorAgent{},  # Stateless logic
  bus: :synapse_bus,
  request_subscription: "sub-123",
  result_subscription: "sub-456",
  active_reviews: %{
    "r123" => %{
      status: :awaiting,
      pending_specialists: ["security_specialist", "performance_specialist"],
      results: [],
      classification: %{path: :deep_review},
      started_at: ~U[2025-10-29 12:00:00Z]
    }
  }
}
```

**Location**: `lib/synapse/agents/coordinator_agent_server.ex` (384 lines)

---

#### SecurityAgentServer

**Responsibility**: Security vulnerability detection

**Actions**:
- `Synapse.Actions.Security.CheckSQLInjection`
- `Synapse.Actions.Security.CheckXSS`
- `Synapse.Actions.Security.CheckAuthIssues`

**Signal Flow**:
```
review.request
  ↓
Execute security actions
  ↓
Emit review.result (findings)
```

**Location**: `lib/synapse/agents/security_agent_server.ex` (264 lines)

---

#### PerformanceAgentServer

**Responsibility**: Performance analysis

**Actions**:
- `Synapse.Actions.Performance.CheckComplexity`
- `Synapse.Actions.Performance.CheckMemoryUsage`
- `Synapse.Actions.Performance.ProfileHotPath`

**Signal Flow**: Same pattern as SecurityAgent

**Location**: `lib/synapse/agents/performance_agent_server.ex` (264 lines)

---

### 4. Action Layer

**Architecture**: Jido actions are composable units

```elixir
defmodule Synapse.Actions.Security.CheckSQLInjection do
  use Jido.Action,
    name: "check_sql_injection",
    schema: [
      diff: [type: :string, required: true],
      files: [type: {:list, :string}, default: []],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _context) do
    findings = analyze_diff_for_sql_injection(params.diff)

    {:ok, %{
      findings: findings,
      summary: "Checked #{length(params.files)} files",
      confidence: calculate_confidence(findings)
    }}
  end
end
```

**Features**:
- Schema validation via NimbleOptions
- Pure functions (no side effects)
- Compensation support for failures
- Telemetry instrumentation

**Location**: `lib/synapse/actions/` (11 action files)

---

### 5. LLM Integration

#### ReqLLM Client

**Architecture**: Multi-provider HTTP client with retry logic

```elixir
defmodule Synapse.ReqLLM do
  def chat_completion(params, opts) do
    with {:ok, config} <- fetch_config(),
         {:ok, profile_name, profile_config} <- resolve_profile(config, opts),
         {:ok, model} <- resolve_model(...),
         {:ok, request} <- build_request(profile_config),
         {:ok, response} <- execute_request(...) do
      parse_response(response, provider_module)
    end
  end
end
```

**Features**:
- Multi-profile support (switch providers per request)
- Automatic retry with exponential backoff
- Telemetry events (start/stop/exception)
- System prompt precedence (request > profile > global)
- Token usage tracking
- Error translation per provider

**Configuration**:
```elixir
config :synapse, Synapse.ReqLLM,
  default_profile: :gemini,
  profiles: %{
    gemini: [
      base_url: "https://generativelanguage.googleapis.com",
      api_key: System.get_env("GEMINI_API_KEY"),
      model: "gemini-flash-lite-latest",
      endpoint: "/v1beta/models/{model}:generateContent",
      payload_format: :google_generate_content,
      auth_header: "x-goog-api-key",
      req_options: [receive_timeout: 30_000]
    ],
    openai: [
      base_url: "https://api.openai.com",
      api_key: System.get_env("OPENAI_API_KEY"),
      model: "gpt-4o-mini",
      req_options: [receive_timeout: 600_000]
    ]
  }
```

**Location**: `lib/synapse/req_llm.ex` (650 lines)

---

#### Provider Adapters

**Interface**: `Synapse.LLMProvider` behaviour

```elixir
defmodule Synapse.LLMProvider do
  @callback prepare_body(params, profile_config, global_config) :: map()
  @callback parse_response(response, metadata) :: {:ok, map()} | {:error, Error.t()}
  @callback translate_error(error, metadata) :: Error.t()
  @callback supported_features() :: [atom()]
  @callback default_config() :: keyword()
end
```

**Implementations**:
- `Synapse.Providers.OpenAI` - OpenAI API format
- `Synapse.Providers.Gemini` - Google Gemini API format

**Location**: `lib/synapse/providers/` (2 files)

---

### 6. Declarative Orchestrator (Partial)

**Purpose**: Replace hardcoded GenServers with configuration

#### AgentConfig

**Schema validation**: NimbleOptions

```elixir
defmodule Synapse.Orchestrator.AgentConfig do
  @schema [
    id: [type: :atom, required: true],
    type: [type: {:in, [:specialist, :orchestrator, :custom]}, required: true],
    actions: [type: {:list, :atom}, required: true],
    signals: [
      type: :map,
      required: true,
      keys: [
        subscribes: [type: {:list, :string}, required: true],
        emits: [type: {:list, :string}, required: true]
      ]
    ],
    result_builder: [type: {:fun, 2}],
    state_schema: [type: :keyword_list, default: []]
  ]
end
```

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
      findings: flat_map_findings(results),
      confidence: avg_confidence(results)
    }
  end
}
```

**Location**: `lib/synapse/orchestrator/agent_config.ex` (315 lines)

---

#### Runtime GenServer

**Purpose**: Continuous reconciliation of desired vs actual state

```elixir
defmodule Synapse.Orchestrator.Runtime do
  use GenServer

  # State
  %{
    config_source: "config/agents.exs",
    agent_configs: [%AgentConfig{}, ...],
    running_agents: %{agent_id => pid},
    reconcile_interval: 5_000
  }

  # Reconciliation loop
  def handle_info(:reconcile, state) do
    new_state = Enum.reduce(state.agent_configs, state, fn config, acc ->
      reconcile_single_agent(config, acc)
    end)

    Process.send_after(self(), :reconcile, state.reconcile_interval)
    {:noreply, new_state}
  end

  defp reconcile_single_agent(config, state) do
    case Map.get(state.running_agents, config.id) do
      nil -> spawn_agent_from_config(config, state)
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: state, else: respawn_agent(config, state)
    end
  end
end
```

**Features**:
- Watches configuration source (file or module)
- Validates configurations
- Spawns missing agents
- Respawns crashed agents
- Monitors agent health

**Location**: `lib/synapse/orchestrator/runtime.ex` (543 lines)

---

## Data Flow

### Review Workflow (Deep Review)

```
1. External System
   ↓ HTTP POST /review
2. API Endpoint
   ↓ Creates Signal
3. Signal.Bus
   ↓ Publishes review.request
4. CoordinatorAgentServer (subscribed)
   ↓ Receives signal
   ↓ Classifies: files_changed=50 → deep_review
   ↓ Spawns: SecurityAgent, PerformanceAgent
5. Both Specialists (in parallel)
   ↓ Subscribe to review.request
   ↓ Execute actions
   ↓ Emit review.result
6. CoordinatorAgentServer (subscribed to review.result)
   ↓ Receives 2x review.result
   ↓ Checks: all specialists responded?
   ↓ Aggregates findings
   ↓ Emits review.summary
7. External System (subscribed to review.summary)
   ↓ Receives final results
```

**Timing**:
- Classification: ~1ms
- Specialist spawn: ~10ms each
- Specialist execution: 20-50ms each (parallel)
- Aggregation: ~5ms
- **Total**: 50-100ms

---

### LLM-Enhanced Review

```
1. SecurityAgent analyzing code
   ↓
2. Executes GenerateCritique action
   ↓
3. ReqLLM.chat_completion
   ↓ Selects profile (gemini)
   ↓ Builds request
   ↓ HTTP POST to Gemini API
4. Gemini processes (200-500ms)
   ↓
5. Response parsed
   ↓
6. Critique returned to SecurityAgent
   ↓
7. Integrated into findings
```

---

## Concurrency Model

### BEAM Processes

Each agent runs as a lightweight BEAM process:

```elixir
# Agents are GenServers
{:ok, pid} = CoordinatorAgentServer.start_link(...)

# Processes are supervised
children = [
  {Jido.Signal.Bus, name: :synapse_bus},
  {Synapse.AgentRegistry, name: :synapse_registry}
  # Agents spawned dynamically
]
```

**Benefits**:
- **Isolation**: Agent crashes don't affect others
- **Scalability**: Millions of processes possible
- **Distribution**: Can run across multiple nodes
- **Hot code reload**: Update code without stopping system

---

### Signal Delivery

**Async by default**:
```elixir
Jido.Signal.Bus.publish(:synapse_bus, [signal])
# Returns immediately, delivery happens async
```

**Dispatch modes**:
- `:async` (default) - Non-blocking
- `:sync` - Blocks until delivered
- `:fire_and_forget` - No guarantees

---

## State Management

### Agent State

Agents maintain state across reviews:

```elixir
%SecurityAgent{
  id: "security_specialist",
  state: %{
    review_history: [
      # Last 100 reviews
      %{review_id: "r1", findings: [...], timestamp: ~U[...]}
    ],
    learned_patterns: [
      # Patterns discovered
      %{pattern: ~r/SELECT.*WHERE.*'/, severity: :high}
    ],
    scar_tissue: [
      # Failures to learn from (last 50)
      %{type: :false_positive, pattern: "...", correction: "..."}
    ]
  }
}
```

**Persistence**: Currently in-memory (future: ETS + snapshots)

---

### Signal History

**Replay capability**:
```elixir
# Get all signals for a review
signals = Jido.Signal.Bus.history(:synapse_bus,
  subject: "jido://review/r123"
)

# Replay for debugging
Enum.each(signals, &Jido.Signal.Bus.publish(:synapse_bus, [&1]))
```

---

## Error Handling

### Action Failures

**Compensation pattern**:
```elixir
defmodule Synapse.Actions.GenerateCritique do
  use Jido.Action,
    compensation: [enabled: true, max_retries: 2]

  @impl true
  def on_error(failed_params, error, context, _opts) do
    Logger.warning("LLM failed, returning compensated result")

    {:ok, %{
      compensated: true,
      original_error: error,
      compensated_at: DateTime.utc_now()
    }}
  end
end
```

---

### Agent Crashes

**Supervision**:
```elixir
# Agents supervised - auto-restart on crash
children = [
  {CoordinatorAgentServer, id: "coordinator", bus: :synapse_bus}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

---

### LLM Failures

**Retry with backoff**:
```elixir
# In ReqLLM
retry: [
  max_attempts: 3,
  base_backoff_ms: 300,
  max_backoff_ms: 5_000
]

# Retries on: 408, 429, 5xx
```

---

## Telemetry

### Events Emitted

```elixir
# LLM requests
[:synapse, :llm, :request, :start]
[:synapse, :llm, :request, :stop]
[:synapse, :llm, :request, :exception]

# Actions (via Jido)
[:jido, :action, :start]
[:jido, :action, :stop]
[:jido, :action, :exception]
```

### Attaching Handlers

```elixir
:telemetry.attach(
  "synapse-llm-logger",
  [:synapse, :llm, :request, :stop],
  fn _name, measurements, metadata, _config ->
    Logger.info("LLM request completed",
      duration: measurements.duration,
      tokens: metadata.token_usage.total_tokens
    )
  end,
  nil
)
```

---

## Testing Strategy

### Unit Tests

```elixir
# Action tests
test "CheckSQLInjection detects interpolation" do
  {:ok, result} = Jido.Exec.run(
    CheckSQLInjection,
    %{diff: "SELECT * WHERE id = '\#{user_input}'", files: []}
  )

  assert length(result.findings) > 0
end
```

### Integration Tests

```elixir
# Multi-agent orchestration
test "full review workflow" do
  {:ok, coordinator} = CoordinatorAgentServer.start_link(...)

  # Subscribe to summary
  {:ok, _} = Jido.Signal.Bus.subscribe(:synapse_bus, "review.summary", ...)

  # Publish request
  {:ok, signal} = Jido.Signal.new(%{type: "review.request", ...})
  Jido.Signal.Bus.publish(:synapse_bus, [signal])

  # Assert summary received
  assert_receive {:signal, summary}, 5000
  assert summary.type == "review.summary"
end
```

### Mocked LLM Tests

```elixir
# Use Req.Test for mocking
setup do
  Req.Test.expect(stub, fn conn ->
    Req.Test.json(conn, %{
      "candidates" => [%{"content" => %{"parts" => [%{"text" => "OK"}]}}]
    })
  end)
end
```

---

## Deployment Architecture

### Development

```elixir
# Single node, all agents in one VM
mix phx.server
```

### Production (Future)

```
┌─────────────────────────────────────────┐
│           Load Balancer                 │
└────────────┬────────────────────────────┘
             │
       ┌─────┴─────┬─────────────┐
       │           │             │
   ┌───▼────┐  ┌───▼────┐   ┌───▼────┐
   │ Node 1 │  │ Node 2 │   │ Node 3 │
   │        │  │        │   │        │
   │ Signal │  │ Signal │   │ Signal │
   │  Bus   │  │  Bus   │   │  Bus   │
   │ (sync) │  │ (sync) │   │ (sync) │
   └───┬────┘  └───┬────┘   └───┬────┘
       │           │             │
       └───────────┴─────────────┘
               │
         Shared Signal Bus
        (Kafka/Pulsar)
```

---

## Performance Characteristics

| Operation | Latency | Throughput |
|-----------|---------|------------|
| **Signal publish** | <1ms | 10,000/sec |
| **Agent spawn** | ~10ms | 100/sec |
| **Action execution** | 1-50ms | Varies |
| **LLM call** | 200-2000ms | Rate limited |
| **Full review (fast)** | <2ms | 500/sec |
| **Full review (deep)** | 50-100ms | 100/sec |

**Bottlenecks**:
- AgentRegistry (single GenServer)
- LLM API rate limits
- Network I/O for signals (if distributed)

---

## Security Considerations

### API Keys
- Stored in environment variables
- Never logged
- Validated at startup

### Input Validation
- All actions use NimbleOptions schemas
- Diff size limits (prevent DoS)
- File path validation

### Agent Isolation
- Agents run in separate processes
- Crashes isolated
- No shared mutable state

---

## Future Enhancements

### Short Term (Stage 3)
- Timeout handling for specialists
- Circuit breakers for LLM calls
- Metrics dashboard (LiveView)

### Medium Term (Stage 4)
- Distributed signal bus (Kafka)
- Agent marketplace
- Dynamic agent registration

### Long Term (Stage 5-6)
- Multi-datacenter deployment
- Learning mesh with gossip protocol
- LLM-generated tools

---

**Architecture Owner**: Engineering Team
**Last Updated**: 2025-10-29
**Next Review**: Stage 3 design (Q1 2026)
