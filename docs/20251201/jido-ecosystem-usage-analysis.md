# Jido Ecosystem Usage Analysis in Synapse

**Date:** 2024-12-01
**Version:** v0.1.1 (Jido & Jido Signal)

## Executive Summary

This report provides a comprehensive analysis of how much Synapse leverages from the Jido ecosystem (`jido` and `jido_signal` dependencies). The analysis reveals that Synapse uses a **focused subset** of the available functionality, primarily centered around:

- **Actions**: Core execution unit - heavily used (18 implementations)
- **Agents**: Stateful executors - moderately used (3 implementations)
- **Signals/Bus**: Event-driven messaging - used via wrapper abstraction
- **Error handling**: Structured errors - consistently used

However, many advanced features remain **untapped**, presenting opportunities for future enhancement.

---

## Table of Contents

1. [Jido Core Library Analysis](#1-jido-core-library-analysis)
2. [Jido Signal Library Analysis](#2-jido-signal-library-analysis)
3. [Current Synapse Usage](#3-current-synapse-usage)
4. [Gap Analysis](#4-gap-analysis)
5. [Usage Statistics](#5-usage-statistics)
6. [Recommendations](#6-recommendations)

---

## 1. Jido Core Library Analysis

### 1.1 Available Modules (47 total)

| Category | Module Count | Key Modules |
|----------|--------------|-------------|
| Core Framework | 3 | `Jido`, `Jido.Application`, `Jido.Supervisor` |
| Action System | 8 | `Jido.Action`, `Jido.Actions.*` (Basic, Arithmetic, Files, etc.) |
| Agent System | 12 | `Jido.Agent`, `Jido.Agent.Server.*` (State, Router, Callback, etc.) |
| Directive System | 1 | `Jido.Agent.Directive` |
| Instruction System | 1 | `Jido.Instruction` |
| Runner System | 3 | `Jido.Runner`, `Jido.Runner.Simple`, `Jido.Runner.Chain` |
| Execution System | 3 | `Jido.Exec`, `Jido.Exec.Chain`, `Jido.Exec.Closure` |
| Sensor System | 4 | `Jido.Sensor`, `Jido.Sensors.Heartbeat/Bus/Cron` |
| Skill System | 3 | `Jido.Skill`, `Jido.Skills.Arithmetic`, `Jido.Skills.Tasks` |
| Discovery | 1 | `Jido.Discovery` |
| Error Handling | 1 | `Jido.Error` |
| Telemetry | 1 | `Jido.Telemetry` |
| Utilities | 2 | `Jido.Util`, `Jido.Scheduler` |

### 1.2 Key Feature Inventory

#### Actions (`Jido.Action`)
- **Behavior definition** with schema validation (NimbleOptions)
- **Lifecycle callbacks**: `on_before_validate_params/1`, `on_after_validate_params/1`, `on_before_validate_output/1`, `on_after_validate_output/1`, `on_after_run/1`, `on_error/4`
- **Compensation mechanism** for retry/rollback on failure
- **Tool conversion** for LLM integration (`to_tool/0`, `to_json/0`)
- **Output schema validation**

#### Built-in Actions
| Action | Purpose |
|--------|---------|
| `Jido.Actions.Basic.Sleep` | Pause execution |
| `Jido.Actions.Basic.Log` | Log messages |
| `Jido.Actions.Basic.Noop` | No-operation |
| `Jido.Actions.Basic.Increment/Decrement` | Numeric operations |
| `Jido.Actions.Arithmetic.*` | Add, Subtract, Multiply, Divide |
| `Jido.Actions.Files.*` | Read, Write, Delete, ListDirectory |
| `Jido.Actions.Directives.*` | RegisterAction, DeregisterAction |
| `Jido.Actions.Req` | HTTP requests |
| `Jido.Actions.StateManager` | State manipulation |
| `Jido.Actions.Tasks` | Task management |

#### Agents (`Jido.Agent`)
- **Stateful entity** with schema-validated state
- **Action registration** at definition or runtime
- **Instruction queue** for pending operations
- **Custom runners** (Simple, Chain)
- **Lifecycle callbacks**: `mount/2`, `shutdown/2`, `handle_signal/2`, `on_before_plan/3`, `on_before_run/1`, `on_after_run/3`, `on_error/2`
- **GenServer integration** via `Jido.Agent.Server`
- **Hot code reload** support (`code_change/3`)

#### Directives (`Jido.Agent.Directive`)
- `Enqueue` - Add instruction to queue
- `StateModification` - `:set`, `:update`, `:delete`, `:reset` operations
- `RegisterAction` / `DeregisterAction` - Dynamic action management
- `Spawn` / `Kill` - Process management

#### Runners
| Runner | Purpose |
|--------|---------|
| `Jido.Runner.Simple` | Single instruction execution |
| `Jido.Runner.Chain` | Sequential multi-instruction with result flowing |

#### Sensors (`Jido.Sensor`)
- **GenServer-based** monitoring
- **Signal generation** via `deliver_signal/1`
- **Configuration validation**
- **Built-in sensors**: Heartbeat, Bus (PubSub), Cron

#### Skills (`Jido.Skill`)
- **Feature packs** bundling actions
- **Signal pattern matching** for routing
- **State isolation** via `opts_key`
- **Process supervision**

#### Execution (`Jido.Exec`)
- **Synchronous execution** with timeout and retry
- **Asynchronous execution** (`run_async/4`, `await/2`, `cancel/1`)
- **Exponential backoff** retry
- **Compensation** on failure
- **Telemetry integration**

#### Discovery (`Jido.Discovery`)
- **Component registry** with caching
- **Slug-based lookup** for actions, sensors, agents, skills
- **Filtering** by name, category, tags

---

## 2. Jido Signal Library Analysis

### 2.1 Available Modules (44+ total)

| Category | Module Count | Key Modules |
|----------|--------------|-------------|
| Core Signal | 2 | `Jido.Signal`, `Jido.Signal.Error` |
| ID Generation | 1 | `Jido.Signal.ID` (UUID7) |
| Router System | 3 | `Jido.Signal.Router`, `Router.Engine`, `Router.Validator` |
| Dispatch System | 10 | `Dispatch`, 9 Adapters (PID, Named, PubSub, Logger, Console, NoOp, HTTP, Webhook, Bus) |
| Bus System | 9 | `Bus`, `BusState`, `BusSubscriber`, `RecordedSignal`, `PersistentSubscription`, `BusStream`, `BusSnapshot`, `MiddlewarePipeline`, `Middleware` |
| Journal System | 4 | `Journal`, `Persistence`, InMemory/ETS Adapters |
| Registry | 1 | `Registry` |
| Serialization | 8 | `Serializer`, 4 implementations (JSON, Erlang Term, MessagePack), TypeProvider, Config |
| Topology | 1 | `Topology` |
| Utilities | 2 | `Util`, `Application` |

### 2.2 Key Feature Inventory

#### Signal Struct (`Jido.Signal`)
CloudEvents v1.0.2 compliant with Jido extensions:
- `specversion`, `id`, `source`, `type`, `subject`, `time`
- `datacontenttype`, `dataschema`, `data`
- `jido_dispatch` - Routing configuration extension

#### Custom Signal Types
```elixir
use Jido.Signal,
  type: "domain.entity.action",
  schema: [field: [type: :string, required: true]]
```

#### Router System
- **Trie-based routing** for O(n) pattern matching
- **Path patterns**: exact (`"user.created"`), single wildcard (`"user.*.updated"`), multi-wildcard (`"audit.**"`)
- **Priority ordering** (-100 to 100)
- **Match functions** for conditional routing

#### Dispatch Adapters
| Adapter | Purpose | Status in Synapse |
|---------|---------|-------------------|
| `PID` | Direct process delivery | **Used** (async mode) |
| `Named` | Registry-based process delivery | Not used |
| `PubSub` | Phoenix.PubSub broadcast | Not used |
| `Logger` | Log signals | Not used |
| `Console` | Print to stdout | Not used |
| `NoOp` | Testing/development | Not used |
| `HTTP` | HTTP POST with retry | Not used |
| `Webhook` | HMAC-signed webhooks | Not used |
| `Bus` | Route to another bus | Unsupported |

#### Bus System (`Jido.Signal.Bus`)
- **Publish/Subscribe** with pattern matching
- **Persistent subscriptions** with acknowledgment
- **Signal replay** from timestamp
- **Snapshots** for point-in-time captures
- **Streams** for ordered signal access
- **Middleware pipeline** (before/after publish/dispatch)

#### Journal System
- **Causality tracking** (cause → effect chains)
- **Conversation grouping**
- **Temporal queries**
- **Cycle detection**
- **Adapters**: InMemory, ETS

#### Serialization
| Serializer | Format | Status |
|------------|--------|--------|
| `JsonSerializer` | JSON | Default |
| `ErlangTermSerializer` | `:erlang.term_to_binary` | Available |
| `MsgpackSerializer` | MessagePack | Available |

#### Middleware
- `before_publish`, `after_publish`
- `before_dispatch`, `after_dispatch`
- Built-in: `Logger` middleware

#### Topology
- Process hierarchy tracking
- Parent-child relationships
- State queries across tree
- Visual tree printing

---

## 3. Current Synapse Usage

### 3.1 Jido Core Usage

#### Actions (18 implementations)

| File | Action Name | Purpose |
|------|-------------|---------|
| `lib/synapse/actions/echo.ex` | Echo | Testing action |
| `lib/synapse/actions/critic_review.ex` | CriticReview | Confidence scoring |
| `lib/synapse/actions/generate_critique.ex` | GenerateCritique | LLM critique generation |
| `lib/synapse/orchestrator/actions/run_config.ex` | RunConfig | Orchestrator workflow execution |
| `lib/synapse/domains/code_review/actions/classify_change.ex` | ClassifyChange | Fast-path classification |
| `lib/synapse/domains/code_review/actions/generate_summary.ex` | GenerateSummary | Review synthesis |
| `lib/synapse/domains/code_review/actions/decide_escalation.ex` | DecideEscalation | Escalation logic |
| `lib/synapse/domains/code_review/actions/security/check_sql_injection.ex` | CheckSqlInjection | SQL injection detection |
| `lib/synapse/domains/code_review/actions/security/check_xss.ex` | CheckXss | XSS detection |
| `lib/synapse/domains/code_review/actions/security/check_auth_issues.ex` | CheckAuthIssues | Auth bypass detection |
| `lib/synapse/domains/code_review/actions/performance/check_complexity.ex` | CheckComplexity | Cyclomatic complexity |
| `lib/synapse/domains/code_review/actions/performance/check_memory_usage.ex` | CheckMemoryUsage | Memory allocation issues |
| `lib/synapse/domains/code_review/actions/performance/profile_hot_path.ex` | ProfileHotPath | Performance hotspots |
| `lib/synapse/workflows/security_specialist_workflow.ex` | StepRunner (nested) | Dynamic action execution |
| `lib/synapse/workflows/performance_specialist_workflow.ex` | StepRunner (nested) | Dynamic action execution |

**Features Used:**
- `use Jido.Action` with name, description, schema
- `run/2` callback (all)
- `on_before_validate_params/1` (ClassifyChange, CheckComplexity)
- `on_error/4` compensation (GenerateCritique)
- Schema validation with NimbleOptions

**Features NOT Used:**
- `on_after_validate_params/1`
- `on_before_validate_output/1`, `on_after_validate_output/1`
- `on_after_run/1`
- Output schema validation
- `to_tool/0`, `to_json/0` for LLM integration
- Any built-in actions (`Jido.Actions.*`)

#### Agents (3 implementations)

| File | Agent Name | Purpose |
|------|------------|---------|
| `lib/synapse/agents/simple_executor.ex` | SimpleExecutor | Testing/demo |
| `lib/synapse/agents/critic_agent.ex` | CriticAgent | Learning from feedback |
| `lib/synapse/orchestrator/generic_agent.ex` | GenericAgent | Runtime orchestrator |

**Features Used:**
- `use Jido.Agent` with name, actions, schema
- `on_before_run/1`, `on_after_run/3` callbacks
- `set/3` for state updates
- Schema-validated state

**Features NOT Used:**
- `start_link/1` for GenServer mode
- `Jido.Agent.Server` infrastructure
- `mount/2`, `shutdown/2`, `handle_signal/2`
- `on_before_plan/3`, `on_error/2`
- Directive system (Enqueue, StateModification, Spawn, Kill)
- Instruction queue (`plan/3`, `run/2`, `cmd/4`)
- `Jido.Runner.Chain` for multi-step execution
- Dynamic action registration at runtime

#### Execution (`Jido.Exec`)

| File | Usage |
|------|-------|
| `lib/synapse/orchestrator/dynamic_agent.ex` | `Jido.Exec.run(RunConfig, params, %{})` |
| `lib/synapse/workflow/engine.ex` | `Jido.Exec.run(step.action, params, context)` |
| Workflow StepRunners | `Jido.Exec.run(action, payload, %{})` |

**Features Used:**
- Synchronous `run/3` execution
- Error tuple handling

**Features NOT Used:**
- `run_async/4`, `await/2`, `cancel/1`
- Timeout configuration
- Retry with exponential backoff
- Compensation mechanism via Exec

#### Error Handling (`Jido.Error`)

| File | Usage |
|------|-------|
| `lib/synapse/actions/generate_critique.ex` | Pattern matching, field access |
| `lib/synapse/providers/openai.ex` | `Error.execution_error(...)` |
| `lib/synapse/providers/gemini.ex` | `Error.execution_error(...)` |
| `lib/synapse/llm_provider.ex` | Type specification |
| `lib/synapse/req_llm.ex` | Type specification |
| `lib/synapse/workflows/chain_helpers.ex` | `Jido.Error.validation_error(...)` |
| Workflow files | `Jido.Error.validation_error(...)` |
| `lib/synapse/workflow/engine.ex` | Serialize error struct |

**Features Used:**
- `validation_error/3`, `execution_error/3`
- Error struct field access (`.type`, `.message`)
- Type specifications

**Features NOT Used:**
- `config_error`, `invalid_action`, `invalid_sensor`
- `planning_error`, `action_error`, `bad_request`
- `internal_server_error`, `timeout`, `invalid_async_ref`
- `compensation_error`, `routing_error`, `dispatch_error`
- `to_map/1`, `capture_stacktrace/0`

### 3.2 Jido Signal Usage

#### Core Signal Operations

| File | Operations |
|------|------------|
| `lib/synapse/signal_router.ex` | `Bus.publish`, `Bus.subscribe`, `Bus.unsubscribe`, `Bus.replay`, `Bus.start_link`, `Signal.new` |
| `lib/synapse/orchestrator/actions/run_config.ex` | `SignalRouter.publish`, `Signal.type`, `Signal.validate!` |
| `lib/synapse/orchestrator/dynamic_agent.ex` | `SignalRouter.subscribe`, `SignalRouter.unsubscribe`, signal handling |
| `lib/synapse/examples/stage_2_demo.ex` | Pattern matching on `%Jido.Signal{}` |

**Features Used:**
- `Jido.Signal.Bus.start_link/1` - Bus initialization
- `Jido.Signal.Bus.publish/2` - Signal emission
- `Jido.Signal.Bus.subscribe/3` - Topic subscription with PID dispatch
- `Jido.Signal.Bus.unsubscribe/2` - Subscription cleanup
- `Jido.Signal.Bus.replay/4` - Historical signal retrieval
- `Jido.Signal.new/1` - Signal creation
- PID adapter with async delivery mode

**Features NOT Used:**
- Custom signal types via `use Jido.Signal`
- Router pattern matching (trie-based routing)
- Named, PubSub, Logger, Console, HTTP, Webhook dispatchers
- Persistent subscriptions with acknowledgment
- Signal snapshots
- Signal streams
- Middleware pipeline
- Journal/causality tracking
- Serialization (JSON, MsgPack, Erlang Term)
- Topology tracking

#### Signal Registry & Domains

| File | Purpose |
|------|---------|
| `lib/synapse/signal.ex` | Canonical facade |
| `lib/synapse/signal/registry.ex` | ETS-backed topic registry |
| `lib/synapse/signal/schema.ex` | Schema helper macro |
| `lib/synapse/domains/code_review.ex` | Domain topic registration |

**Topics Registered:**
- `:review_request` → `"review.request"`
- `:review_result` → `"review.result"`
- `:review_summary` → `"review.summary"`
- `:specialist_ready` → `"review.specialist_ready"`

---

## 4. Gap Analysis

### 4.1 Jido Core - Unused Features

| Category | Feature | Potential Use Case |
|----------|---------|-------------------|
| **Actions** | `to_tool/0`, `to_json/0` | LLM function calling integration |
| **Actions** | Output schema validation | Ensure action results match expected shape |
| **Actions** | Built-in actions (`Files`, `Req`, etc.) | Reduce boilerplate for common operations |
| **Agents** | GenServer mode (`start_link/1`) | Long-running stateful agents |
| **Agents** | `handle_signal/2` callback | Native signal handling in agents |
| **Agents** | Instruction queue | Deferred execution patterns |
| **Agents** | `Jido.Runner.Chain` | Multi-step atomic operations |
| **Directives** | State modification directives | Declarative state transitions |
| **Directives** | Spawn/Kill directives | Dynamic process management |
| **Sensors** | `Jido.Sensor` behavior | Monitoring/event emission |
| **Sensors** | Heartbeat, Cron sensors | Scheduled tasks, health checks |
| **Skills** | `Jido.Skill` behavior | Reusable capability bundles |
| **Exec** | Async execution | Non-blocking action execution |
| **Exec** | Retry with backoff | Resilient external calls |
| **Discovery** | Component registry | Dynamic action/agent lookup |
| **Telemetry** | `Jido.Telemetry` | Metrics and tracing |

### 4.2 Jido Signal - Unused Features

| Category | Feature | Potential Use Case |
|----------|---------|-------------------|
| **Signal Types** | `use Jido.Signal` macro | Type-safe custom signals |
| **Router** | Trie-based pattern matching | Wildcard subscriptions (`"review.**"`) |
| **Router** | Priority ordering | Control handler execution order |
| **Dispatch** | Named adapter | Registry-based process lookup |
| **Dispatch** | PubSub adapter | Cross-node broadcasting |
| **Dispatch** | HTTP adapter | External webhook integration |
| **Dispatch** | Webhook adapter | Signed external delivery |
| **Dispatch** | Logger adapter | Signal auditing |
| **Bus** | Persistent subscriptions | Reliable delivery with ack |
| **Bus** | Snapshots | Point-in-time signal captures |
| **Bus** | Streams | Ordered signal consumption |
| **Bus** | Middleware | Cross-cutting concerns (auth, logging) |
| **Journal** | Causality tracking | Debug signal chains |
| **Journal** | Conversation grouping | Related signal correlation |
| **Serialization** | MsgPack/Erlang Term | Compact wire formats |
| **Topology** | Process hierarchy | Visualization, debugging |
| **ID** | UUID7 utilities | Temporal ordering, batch generation |

---

## 5. Usage Statistics

### Overall Coverage

```
┌─────────────────────────────────────────────────────────────────┐
│                    JIDO ECOSYSTEM USAGE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  JIDO CORE (47 modules)                                         │
│  ████████░░░░░░░░░░░░░░░░░░░░░░  ~25% utilized                  │
│                                                                 │
│  • Actions:      ████████████████████  HEAVILY USED             │
│  • Agents:       ████████░░░░░░░░░░░░  MODERATELY USED          │
│  • Exec:         ██████░░░░░░░░░░░░░░  BASIC SYNC ONLY          │
│  • Error:        ████████░░░░░░░░░░░░  PARTIAL COVERAGE         │
│  • Sensors:      ░░░░░░░░░░░░░░░░░░░░  NOT USED                 │
│  • Skills:       ░░░░░░░░░░░░░░░░░░░░  NOT USED                 │
│  • Discovery:    ░░░░░░░░░░░░░░░░░░░░  NOT USED                 │
│  • Telemetry:    ░░░░░░░░░░░░░░░░░░░░  NOT USED                 │
│  • Directives:   ░░░░░░░░░░░░░░░░░░░░  NOT USED                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  JIDO SIGNAL (44+ modules)                                      │
│  ██████░░░░░░░░░░░░░░░░░░░░░░░░  ~15% utilized                  │
│                                                                 │
│  • Signal Struct: ████████████████████  USED                    │
│  • Bus Pub/Sub:   ████████████████░░░░  BASIC OPERATIONS        │
│  • PID Dispatch:  ████████████████████  USED (ASYNC)            │
│  • Replay:        ████████░░░░░░░░░░░░  BASIC USAGE             │
│  • Router:        ░░░░░░░░░░░░░░░░░░░░  NOT USED                │
│  • Other Adapt:   ░░░░░░░░░░░░░░░░░░░░  NOT USED                │
│  • Middleware:    ░░░░░░░░░░░░░░░░░░░░  NOT USED                │
│  • Journal:       ░░░░░░░░░░░░░░░░░░░░  NOT USED                │
│  • Serialization: ░░░░░░░░░░░░░░░░░░░░  NOT USED                │
│  • Topology:      ░░░░░░░░░░░░░░░░░░░░  NOT USED                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### File-Level Statistics

| Category | Files Using | Unique Features Used |
|----------|-------------|---------------------|
| `use Jido.Action` | 18 | 5 of 10 callbacks |
| `use Jido.Agent` | 3 | 4 of 12 callbacks |
| `alias Jido.Exec` | 4 | 1 of 5 functions |
| `alias Jido.Error` | 8 | 2 of 15 error types |
| `Jido.Signal.*` direct | 2 | 5 of 20+ functions |
| `SignalRouter` (wrapper) | 6 | Subset of Bus API |

---

## 6. Recommendations

### 6.1 Quick Wins (Low Effort, High Value)

1. **Enable Output Schema Validation**
   - Add `output_schema` to critical actions
   - Catches type errors at action boundaries

2. **Use `to_tool/0` for LLM Integration**
   - Convert actions to OpenAI function format automatically
   - Useful for GenerateCritique and similar LLM actions

3. **Add Logger Middleware to Bus**
   ```elixir
   {Jido.Signal.Bus.Middleware.Logger, [level: :debug, include_signal_data: true]}
   ```

4. **Leverage Built-in Actions**
   - Replace custom file operations with `Jido.Actions.Files.*`
   - Use `Jido.Actions.Req` for HTTP calls

### 6.2 Medium-Term Enhancements

1. **Implement Sensors for Monitoring**
   - `HeartbeatSensor` for agent health
   - Custom sensors for system metrics

2. **Use Async Execution for LLM Calls**
   ```elixir
   ref = Jido.Exec.run_async(GenerateCritique, params, context)
   # ... do other work ...
   {:ok, result} = Jido.Exec.await(ref, timeout: 30_000)
   ```

3. **Enable Persistent Subscriptions**
   - Ensure reliable delivery for critical signals
   - Implement acknowledgment in DynamicAgent

4. **Add Causality Tracking via Journal**
   - Debug complex signal chains
   - Understand review request → result → summary flow

### 6.3 Architectural Opportunities

1. **Adopt Skills for Specialist Capabilities**
   - Bundle security checks into `SecuritySkill`
   - Bundle performance checks into `PerformanceSkill`
   - Enable plug-and-play specialist modules

2. **Use Agent GenServer Mode**
   - Long-running orchestrator agents
   - Native signal handling via `handle_signal/2`
   - Supervision tree integration

3. **Leverage Router Pattern Matching**
   - Subscribe to `"review.**"` for all review signals
   - Priority-based handler ordering

4. **Implement Discovery for Dynamic Actions**
   - Runtime action/agent registration
   - Category-based filtering for specialists

### 6.4 Future Considerations

1. **External Integrations**
   - HTTP/Webhook dispatchers for external services
   - PubSub adapter for multi-node deployment

2. **Observability**
   - Integrate `Jido.Telemetry` for metrics
   - Topology tracking for process visualization

3. **Serialization Optimization**
   - MessagePack for high-throughput signal paths
   - Type providers for struct preservation

---

## Appendix A: Module Cross-Reference

### Jido Core Modules → Synapse Usage

| Jido Module | Used? | Synapse Files |
|-------------|-------|---------------|
| `Jido` | No | - |
| `Jido.Action` | **Yes** | 18 files |
| `Jido.Actions.*` | No | - |
| `Jido.Agent` | **Yes** | 3 files |
| `Jido.Agent.Server` | No | - |
| `Jido.Agent.Directive` | No | - |
| `Jido.Instruction` | No | - |
| `Jido.Runner` | No | - |
| `Jido.Runner.Simple` | Implicit | Default runner |
| `Jido.Runner.Chain` | No | - |
| `Jido.Exec` | **Yes** | 4 files |
| `Jido.Sensor` | No | - |
| `Jido.Sensors.*` | No | - |
| `Jido.Skill` | No | - |
| `Jido.Skills.*` | No | - |
| `Jido.Discovery` | No | - |
| `Jido.Error` | **Yes** | 8 files |
| `Jido.Telemetry` | No | - |
| `Jido.Util` | No | - |

### Jido Signal Modules → Synapse Usage

| Jido Signal Module | Used? | Synapse Files |
|--------------------|-------|---------------|
| `Jido.Signal` | **Yes** | 2 files (direct), 6 via wrapper |
| `Jido.Signal.Bus` | **Yes** | Via SignalRouter |
| `Jido.Signal.Router` | No | - |
| `Jido.Signal.Dispatch.PID` | **Yes** | Via Bus |
| `Jido.Signal.Dispatch.*` (others) | No | - |
| `Jido.Signal.Bus.Middleware` | No | - |
| `Jido.Signal.Journal` | No | - |
| `Jido.Signal.Registry` | No | Custom registry |
| `Jido.Signal.Serialization.*` | No | - |
| `Jido.Signal.Topology` | No | - |
| `Jido.Signal.ID` | Implicit | Via Signal.new |
| `Jido.Signal.Error` | No | Uses Jido.Error |

---

## Appendix B: Synapse Files Using Jido

### Actions
- `lib/synapse/actions/echo.ex`
- `lib/synapse/actions/critic_review.ex`
- `lib/synapse/actions/generate_critique.ex`
- `lib/synapse/orchestrator/actions/run_config.ex`
- `lib/synapse/domains/code_review/actions/classify_change.ex`
- `lib/synapse/domains/code_review/actions/generate_summary.ex`
- `lib/synapse/domains/code_review/actions/decide_escalation.ex`
- `lib/synapse/domains/code_review/actions/security/check_sql_injection.ex`
- `lib/synapse/domains/code_review/actions/security/check_xss.ex`
- `lib/synapse/domains/code_review/actions/security/check_auth_issues.ex`
- `lib/synapse/domains/code_review/actions/performance/check_complexity.ex`
- `lib/synapse/domains/code_review/actions/performance/check_memory_usage.ex`
- `lib/synapse/domains/code_review/actions/performance/profile_hot_path.ex`
- `lib/synapse/workflows/security_specialist_workflow.ex` (StepRunner)
- `lib/synapse/workflows/performance_specialist_workflow.ex` (StepRunner)

### Agents
- `lib/synapse/agents/simple_executor.ex`
- `lib/synapse/agents/critic_agent.ex`
- `lib/synapse/orchestrator/generic_agent.ex`

### Signal Infrastructure
- `lib/synapse/signal.ex`
- `lib/synapse/signal_router.ex`
- `lib/synapse/signal/registry.ex`
- `lib/synapse/signal/schema.ex`
- `lib/synapse/domains/code_review.ex`
- `lib/synapse/orchestrator/dynamic_agent.ex`
- `lib/synapse/orchestrator/actions/run_config.ex`

### Error Handling
- `lib/synapse/providers/openai.ex`
- `lib/synapse/providers/gemini.ex`
- `lib/synapse/llm_provider.ex`
- `lib/synapse/req_llm.ex`
- `lib/synapse/workflow/engine.ex`
- `lib/synapse/workflows/chain_helpers.ex`

---

*Report generated: 2024-12-01*
*Jido Version: v0.1.1*
*Jido Signal Version: v0.1.1*
