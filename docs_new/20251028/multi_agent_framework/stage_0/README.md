# Stage 0 – Foundation Infrastructure

## Purpose

Stage 0 establishes the **actual working infrastructure** needed before building the multi-agent review system. This is the foundation that makes agents autonomous and signal-driven.

## What's Missing from Stage 1

Stage 1 delivered:
- ✅ Actions (security, performance checks)
- ✅ Agent structs (data structures)
- ✅ State helpers (record_history, learn_from_correction)
- ✅ Tests (151 passing)

But we don't have:
- ❌ Agents running as processes
- ❌ Signal.Bus integration
- ❌ Signal-based communication
- ❌ Directive processing (Spawn, Enqueue)
- ❌ Autonomous behavior
- ❌ Observable running system

## Stage 0 Scope

### 1. Signal Infrastructure
- Agents subscribe to Signal.Bus on startup
- Agents emit signals when completing work
- Signal routing via Jido.Signal.Router
- Signal contracts tested end-to-end

### 2. Process Management
- GenServer-based agents (Jido.Agent.Server)
- AgentRegistry spawns actual processes
- Supervision tree integration
- Process monitoring and restart

### 3. Directive System
- Agents emit Directive.Enqueue after actions
- CoordinatorAgent emits Directive.Spawn
- Directives actually processed by server
- Observable directive flow

### 4. Living Example
- Single specialist agent (SecurityAgent) running as GenServer
- Receives `review.request` signal from bus
- Executes CheckSQLInjection action
- Emits `review.result` signal
- Observable via logs and telemetry

### 5. Documentation
- README with running example
- Architecture showing actual signal flow
- Troubleshooting common issues
- Getting started guide

## Deliverables

| Path | Description |
| --- | --- |
| `lib/synapse/agents/server_behaviours.ex` | Shared GenServer callbacks for stateful agents |
| `lib/synapse/application.ex` | Updated with Signal.Bus and agent supervision |
| `test/synapse/integration/signal_bus_flow_test.exs` | Actual signal bus integration test |
| `test/synapse/integration/process_lifecycle_test.exs` | Agent spawning and monitoring test |
| `docs/20251028/multi_agent_framework/stage_0/GETTING_STARTED.md` | How to run the system |
| `docs/20251028/multi_agent_framework/stage_0/EXAMPLE.md` | Copy-paste working example |

## Success Criteria

1. Run `iex -S mix` and see Signal.Bus start
2. Spawn SecurityAgent and see it subscribe to bus
3. Publish `review.request` signal
4. Observe SecurityAgent receive, process, emit result
5. All observable via Logger output
6. Tests prove it works end-to-end

## Test-Driven Implementation Order

1. **Signal Bus Lifecycle** (test first)
   - Start/stop bus in supervision tree
   - Subscribe to patterns
   - Publish and receive signals

2. **Single GenServer Agent** (test first)
   - SecurityAgent.Server.start_link
   - Subscribes to `review.request` pattern
   - Processes signal, runs actions
   - Emits `review.result` signal

3. **Directive Processing** (test first)
   - Agent emits Directive.Enqueue after action
   - Server processes directive
   - Queued instruction executed

4. **AgentRegistry Integration** (test first)
   - Registry spawns GenServer agents
   - Idempotent spawning works
   - Process monitoring works

5. **Living Example** (test first)
   - End-to-end test: publish signal → agent processes → result emitted
   - Observable logs
   - Reproducible in iex

---

This is the foundation that makes everything else possible.
