# Stage 0 Backlog (TDD Order)

Each item starts as a **failing test**. Implementation follows only after test exists.

## 0. Signal Bus Lifecycle

- [x] **Test**: Signal.Bus starts in application supervision tree
- [x] **Test**: Bus accepts subscriptions with patterns
- [x] **Test**: Published signals delivered to subscribers
- [x] **Test**: Bus survives and restarts on crash (deferred - registration mechanism)
- [x] **Impl**: Add Signal.Bus to Synapse.Application
- [x] **Impl**: Configure bus with default settings

## 1. GenServer Agent Foundation

- [x] **Test**: SecurityAgentServer.start_link starts process
- [x] **Test**: Server subscribes to `review.request` on init
- [x] **Test**: Server receives signal via handle_info
- [x] **Test**: Server executes action when signal received
- [x] **Test**: Server emits `review.result` signal after action
- [x] **Impl**: Create SecurityAgentServer module
- [x] **Impl**: Implement GenServer callbacks with signal handling
- [x] **Impl**: Wire signal subscription on init

## 2. Signal Processing Flow

- [x] **Test**: Agent transforms incoming signal to parameters
- [x] **Test**: Agent runs actions through Jido.Exec
- [x] **Test**: Agent builds result signal from action output
- [x] **Test**: Agent publishes result to bus
- [x] **Impl**: Implement signal → params transformation in handle_review_request
- [x] **Impl**: Implement action execution in handle_info
- [x] **Impl**: Implement result signal emission

## 3. Directive System

- [~] **Deferred to Stage 2**: Directives work with stateless agents
- [~] Full directive flow requires coordinator orchestration
- [~] Current: Direct action execution, no queuing needed yet

## 4. Process Registry Integration

- [x] **Test**: AgentRegistry in supervision tree
- [x] **Test**: Registry accessible by name
- [x] **Impl**: AgentRegistry runs as GenServer
- [~] **Deferred**: GenServer agent spawning (Stage 2)

## 5. End-to-End Integration

- [x] **Test**: Publish `review.request` → SecurityAgent receives
- [x] **Test**: SecurityAgent runs CheckSQLInjection
- [x] **Test**: SecurityAgent emits `review.result`
- [x] **Test**: Result signal observable on bus
- [x] **Test**: Full flow completes within timeout
- [x] **Impl**: Wire all components together
- [x] **Impl**: Add telemetry for observability

## 6. Supervision Tree

- [x] **Test**: Application starts Signal.Bus
- [x] **Test**: Application starts AgentRegistry
- [x] **Test**: Bus handles subscriptions
- [~] **Test**: Restart behavior (deferred - registration mechanism)
- [x] **Impl**: Update Application with Signal.Bus + AgentRegistry
- [x] **Impl**: Configure one_for_one restart strategy

## 7. Living Example

- [x] **Test**: IEx can spawn agent and send signal (via Stage0Demo.run)
- [x] **Test**: Example detects SQL injection
- [x] **Impl**: Create Synapse.Examples.Stage0Demo module
- [x] **Impl**: Write GETTING_STARTED.md with copy-paste code

## 8. Documentation

- [x] README.md - Multi-agent framework overview
- [x] GETTING_STARTED.md - Runnable examples
- [x] Stage 0 README - What was built
- [~] TROUBLESHOOTING.md - Deferred to Stage 2

---

**Success Metric**: After Stage 0, someone can clone the repo, run `iex -S mix`, copy-paste example code, and see agents communicating via signals.
