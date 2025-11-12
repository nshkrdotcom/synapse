# API Reference

## Overview

Complete API reference for the Synapse Multi-Agent Framework (Stage 0 + Stage 1).

---

## Agents

### Synapse.Agents.SecurityAgentServer

**Type**: GenServer

Running autonomous security review agent.

#### `start_link/1`

Starts the SecurityAgent GenServer.

**Parameters**:
- `opts` (keyword list)
  - `:id` (required) - Unique agent identifier
  - `:bus` (optional) - Signal.Bus name (default: `:synapse_bus`)
  - `:name` (optional) - GenServer registration name

**Returns**: `{:ok, pid}` or `{:error, reason}`

**Example**:
```elixir
{:ok, pid} = Synapse.Agents.SecurityAgentServer.start_link(
  id: "security_prod",
  bus: :synapse_bus
)
```

---

### Synapse.Agents.SecurityAgent

**Type**: Stateless agent struct

Security specialist data structure with state management helpers.

#### `new/1`

Creates a new SecurityAgent instance.

**Parameters**:
- `agent_id` (string) - Unique identifier

**Returns**: `%SecurityAgent{}`

**Example**:
```elixir
agent = Synapse.Agents.SecurityAgent.new("security_1")
```

#### `record_history/2`

Records a review in the agent's history (circular buffer, last 100).

**Parameters**:
- `agent` - SecurityAgent struct
- `review_metadata` - Map with `:review_id`, `:timestamp`, `:issues_found`

**Returns**: `{:ok, updated_agent}`

**Example**:
```elixir
{:ok, agent} = SecurityAgent.record_history(agent, %{
  review_id: "review_123",
  timestamp: DateTime.utc_now(),
  issues_found: 3
})
```

#### `learn_from_correction/2`

Learns from feedback, updating pattern counts.

**Parameters**:
- `agent` - SecurityAgent struct
- `pattern_payload` - Map with `:pattern` and optional `:example`

**Returns**: `{:ok, updated_agent}`

**Example**:
```elixir
{:ok, agent} = SecurityAgent.learn_from_correction(agent, %{
  pattern: "sql_injection_in_repo",
  example: "Use Repo.query/2 with parameters"
})
```

#### `record_failure/2`

Records a failed attempt as scar tissue (circular buffer, last 50).

**Parameters**:
- `agent` - SecurityAgent struct
- `failure_details` - Map with `:pattern`, `:mitigation`, optional `:details`

**Returns**: `{:ok, updated_agent}`

**Example**:
```elixir
{:ok, agent} = SecurityAgent.record_failure(agent, %{
  pattern: "false_positive_xss",
  mitigation: "Added template context check"
})
```

---

### Synapse.Agents.PerformanceAgent

**Type**: Stateless agent struct

Performance specialist. API identical to SecurityAgent.

**Functions**: `new/1`, `record_history/2`, `learn_from_correction/2`, `record_failure/2`

---

### Synapse.Agents.CoordinatorAgent

**Type**: Stateless agent struct

Orchestrates multi-agent reviews.

#### `new/1`

Creates a coordinator instance.

#### `classify_change/2`

Classifies a change to determine review path.

**Parameters**:
- `agent` - CoordinatorAgent struct
- `review_data` - Map with `:files_changed`, `:labels`, `:intent`, `:risk_factor`

**Returns**: `{:ok, %{path: :fast_path | :deep_review, rationale: string}}`

**Example**:
```elixir
{:ok, classification} = CoordinatorAgent.classify_change(coordinator, %{
  files_changed: 75,
  labels: ["security"],
  intent: "feature",
  risk_factor: 0.3
})
# => %{path: :deep_review, rationale: "..."}
```

#### `start_review/3`

Begins tracking a review.

**Parameters**:
- `agent` - CoordinatorAgent struct
- `review_id` - Review identifier
- `review_state` - Map with `:status`, `:pending_specialists`, `:results`

**Returns**: `{:ok, updated_agent}`

#### `add_specialist_result/3`

Adds a specialist's result to an active review.

**Parameters**:
- `agent` - CoordinatorAgent struct
- `review_id` - Review identifier
- `specialist_result` - Result map from specialist

**Returns**: `{:ok, updated_agent, ready?}` where `ready?` indicates all specialists responded

#### `complete_review/2`

Completes a review, increments count, removes from active.

**Returns**: `{:ok, updated_agent}`

#### `synthesize_results/5`

Synthesizes specialist results into summary.

**Parameters**:
- `agent` - CoordinatorAgent struct
- `review_id` - Review identifier
- `specialist_results` - List of specialist result maps
- `decision_path` - `:fast_path` or `:deep_review`
- `duration_ms` - Total review duration

**Returns**: `{:ok, summary_map}`

---

## Actions

### Security Actions

#### `Synapse.Actions.Security.CheckSQLInjection`

Detects SQL injection vulnerabilities.

**Schema**:
```elixir
%{
  diff: string (required),
  files: [string] (required),
  metadata: map (optional, default: %{})
}
```

**Returns**:
```elixir
{:ok, %{
  findings: [%{type, severity, file, summary, recommendation}],
  confidence: float,
  recommended_actions: [string]
}}
```

**Example**:
```elixir
{:ok, result} = Jido.Exec.run(
  Synapse.Actions.Security.CheckSQLInjection,
  %{
    diff: code_diff,
    files: ["lib/repo.ex"],
    metadata: %{language: "elixir"}
  },
  %{}
)
```

#### `Synapse.Actions.Security.CheckXSS`

Detects XSS vulnerabilities.

**Schema**: Same as CheckSQLInjection

**Detects**: `raw/1` usage, unescaped rendering, innerHTML

#### `Synapse.Actions.Security.CheckAuthIssues`

Detects authentication/authorization issues.

**Schema**: Same as CheckSQLInjection

**Detects**: Removed plugs, bypassed checks, weakened guards

### Performance Actions

#### `Synapse.Actions.Performance.CheckComplexity`

Analyzes cyclomatic complexity.

**Schema**:
```elixir
%{
  diff: string (required),
  language: string (required),
  thresholds: map (optional, default: %{max_complexity: 10})
}
```

**Returns**:
```elixir
{:ok, %{
  findings: [%{type: :high_complexity, severity, file, summary}],
  confidence: float,
  recommended_actions: [string]
}}
```

#### `Synapse.Actions.Performance.CheckMemoryUsage`

Detects greedy memory allocation patterns.

**Schema**:
```elixir
%{
  diff: string (required),
  files: [string] (required),
  metadata: map (optional)
}
```

#### `Synapse.Actions.Performance.ProfileHotPath`

Identifies performance hotspots.

**Schema**: Same as CheckMemoryUsage

### Review Actions

#### `Synapse.Actions.Review.ClassifyChange`

Classifies change as fast_path or deep_review.

**Schema**:
```elixir
%{
  files_changed: non_neg_integer (required),
  labels: [string] (required),
  intent: string (required),
  risk_factor: float (optional, default: 0.0)
}
```

**Returns**:
```elixir
{:ok, %{
  path: :fast_path | :deep_review,
  rationale: string,
  review_id: string (if in context)
}}
```

**Decision Logic**:
- `intent == "hotfix"` → `:fast_path`
- `files_changed > 50` → `:deep_review`
- `"security" or "performance" in labels` → `:deep_review`
- `risk_factor >= 0.5` → `:deep_review`
- Otherwise → `:fast_path`

#### `Synapse.Actions.Review.GenerateSummary`

Synthesizes specialist findings into summary.

**Schema**:
```elixir
%{
  review_id: string (required),
  findings: [map] (required),
  metadata: map (required)
}
```

**Returns**:
```elixir
{:ok, %{
  review_id: string,
  status: :complete | :failed,
  severity: :none | :low | :medium | :high,
  findings: [map],                    # Sorted by severity
  recommendations: [string],
  escalations: [string],
  metadata: map
}}
```

---

## Utilities

### Synapse.AgentRegistry

Process registry for agent management.

#### `get_or_spawn/4`

Gets existing agent or spawns new one (idempotent).

**Parameters**:
- `registry` - Registry name (default: `Synapse.AgentRegistry`)
- `agent_id` - Unique identifier
- `agent_module` - Module to spawn
- `opts` - Options to pass to agent

**Returns**: `{:ok, pid}` or `{:error, reason}`

#### `lookup/2`

Looks up agent by ID.

**Returns**: `{:ok, pid}` or `{:error, :not_found}`

#### `list_agents/1`

Lists all registered agents.

**Returns**: `[{agent_id, pid}]`

---

### Synapse.Examples.Stage0Demo

Live demonstration module.

#### `run/0`

Runs complete demo: starts agent, sends request, shows result.

**Returns**: `{:ok, result_signal}` or `{:error, :timeout}`

#### `health_check/0`

Verifies system is running.

**Returns**:
- `{:ok, "✓ System healthy"}` - All components running
- `{:warning, message}` - Partial functionality
- `{:error, message}` - System not operational

#### `start_security_agent/1`

Starts a SecurityAgentServer instance.

**Parameters**: `opts` (optional keyword list)

**Returns**: `{:ok, pid}`

#### `subscribe_to_results/1`

Subscribes current process to review.result signals.

**Parameters**: `bus` (optional, default: `:synapse_bus`)

**Returns**: `{:ok, subscription_id}`

#### `send_review_request/2`

Publishes a test review.request signal.

**Parameters**:
- `review_id` - Review identifier
- `bus` (optional) - Bus name

**Returns**: `{:ok, review_id}`

#### `wait_for_result/1`

Waits for review.result signal.

**Parameters**: `timeout` (optional, default: 2000ms)

**Returns**: `{:ok, signal}` or `:timeout`

#### `display_result/1`

Pretty-prints a result signal.

**Parameters**: `signal` - Jido.Signal struct

---

## Test Support

### Synapse.TestSupport.SignalRouterHelpers

Helpers for testing with Signal.Bus.

#### `start_test_bus/1`

Starts a test bus with automatic cleanup.

**Returns**: Bus name (atom)

#### `publish_signal/4`

Publishes a signal for testing.

**Parameters**: `bus`, `signal_type`, `data`, `opts`

**Returns**: `signal_id`

#### `await_signal/2`

Waits for signal matching pattern.

**Returns**: `signal` or flunks test

### Synapse.TestSupport.AgentHelpers

Helpers for testing agents.

#### `assert_agent_state/2`

Asserts agent state matches expected values.

**Example**:
```elixir
assert_agent_state(agent, review_count: 1)
assert_agent_state(agent, %{review_count: 1, learned_patterns: []})
```

#### `get_agent_state/1`

Extracts state from agent struct.

#### `exec_agent_cmd/2`

Executes command and returns updated agent.

### Synapse.TestSupport.Factory

Test data generators.

#### `build_review_request/1`

Generates review request payload.

#### `build_review_result/1`

Generates specialist result payload.

#### `build_finding/1`

Generates finding map.

#### `build_review_summary/1`

Generates summary payload.

---

## Signal Schemas

### Complete Signal Type Reference

| Type | Direction | Producer | Consumer |
|------|-----------|----------|----------|
| `review.request` | Input | External system | SecurityAgentServer |
| `review.result` | Output | SecurityAgentServer | Coordinator (future) |
| `review.summary` | Output | Coordinator (future) | External system |

### Signal Field Reference

#### CloudEvents Standard Fields

- `id` - UUID v4 (auto-generated)
- `specversion` - "1.0.2"
- `type` - Signal type (e.g., "review.request")
- `source` - Origin URI (e.g., "/synapse/agents/security_specialist")
- `subject` - Resource URI (e.g., "jido://review/review_123")
- `time` - ISO 8601 timestamp (auto-generated)
- `datacontenttype` - "application/json" (default)
- `data` - Payload (see schemas above)

#### Jido Extensions

- `jido_dispatch` - Dispatch configuration (optional)

---

## Configuration Reference

### Application Configuration

```elixir
# config/config.exs
config :synapse,
  # Signal bus name
  signal_bus: :synapse_bus,
  # Agent registry name
  agent_registry: :synapse_registry

# Logger configuration
config :logger,
  level: :info,  # :debug for development
  backends: [:console]

# Jido configuration
config :jido,
  default_timeout: 30_000,     # Action timeout (ms)
  default_max_retries: 1       # Action retries
```

### Environment-Specific

```elixir
# config/dev.exs
config :logger, level: :debug

# config/test.exs
config :logger, level: :warn
config :jido, default_timeout: 5_000

# config/prod.exs
config :logger, level: :info
config :jido, default_timeout: 60_000
```

---

## Error Reference

### Common Error Types

#### Validation Errors

```elixir
{:error, %Jido.Error{
  type: :validation_error,
  message: "Required parameter missing: diff",
  details: %{...}
}}
```

**Causes**: Missing required parameters, invalid types, constraint violations

**Fix**: Check action schema, provide all required fields

#### Execution Errors

```elixir
{:error, %Jido.Error{
  type: :execution_error,
  message: "Action failed: ...",
  details: %{...}
}}
```

**Causes**: Runtime failures, external service errors

**Fix**: Check logs, verify inputs, retry if transient

#### Timeout Errors

```elixir
{:error, %Jido.Error{
  type: :timeout_error,
  message: "Action exceeded timeout",
  details: %{timeout: 30000, elapsed: 35000}
}}
```

**Causes**: Slow action execution, blocking operations

**Fix**: Increase timeout or optimize action

---

## Telemetry Events

### Jido.Exec Events

```elixir
[:jido, :exec, :start]
# Measurements: %{system_time: integer}
# Metadata: %{action: module, params: map, context: map}

[:jido, :exec, :stop]
# Measurements: %{duration: integer (nanoseconds)}
# Metadata: %{action: module, result: term}

[:jido, :exec, :exception]
# Measurements: %{duration: integer}
# Metadata: %{action: module, error: term, stacktrace: list}
```

### Jido.Signal.Bus Events

```elixir
[:jido, :signal, :publish]
# Measurements: %{count: integer}
# Metadata: %{bus: atom, signals: [signal]}

[:jido, :signal, :dispatch]
# Measurements: %{latency_ms: integer}
# Metadata: %{signal: signal, subscriber: term}
```

---

## Type Specifications

### Agent Types

```elixir
@type agent_id :: String.t()
@type review_id :: String.t()

@type finding :: %{
  type: atom(),
  severity: :none | :low | :medium | :high,
  file: String.t(),
  summary: String.t(),
  recommendation: String.t() | nil
}

@type review_result :: %{
  review_id: review_id(),
  agent: String.t(),
  confidence: float(),
  findings: [finding()],
  should_escalate: boolean(),
  metadata: map()
}

@type review_summary :: %{
  review_id: review_id(),
  status: :complete | :failed,
  severity: :none | :low | :medium | :high,
  findings: [finding()],
  recommendations: [String.t()],
  escalations: [String.t()],
  metadata: map()
}
```

---

## Constants

### Severity Levels

```elixir
:none    # No issues found
:low     # Minor issues, low impact
:medium  # Moderate issues, should fix
:high    # Critical issues, must fix
```

### Review Paths

```elixir
:fast_path    # Quick review, minimal checks
:deep_review  # Thorough review, all specialists
```

### Agent Names

```elixir
"security_specialist"     # SecurityAgent
"performance_specialist"  # PerformanceAgent
"coordinator"            # CoordinatorAgent
```

---

## See Also

- [Architecture](ARCHITECTURE.md) - System design
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
- [Getting Started](stage_0/GETTING_STARTED.md) - Quick start
- [Implementation Summary](IMPLEMENTATION_SUMMARY.md) - What was built
