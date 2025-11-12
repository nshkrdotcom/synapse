# Getting Started with Stage 0

## What You're About to Run

A **real, working multi-agent system** that:
1. Receives code review requests via signals
2. Autonomously analyzes code for security vulnerabilities
3. Emits structured findings
4. All observable in real-time

## Prerequisites

```bash
cd /path/to/synapse
mix deps.get
mix compile
```

## Running the Demo

### Option 1: One-Line Demo

```elixir
iex -S mix
iex> Synapse.Examples.Stage0Demo.run()
```

You'll see:
- Agent starting
- Signal subscription
- Request processing
- **SQL injection detected!**
- Result emitted

### Option 2: Step-by-Step

```elixir
iex -S mix

# 1. Check system health
iex> Synapse.Examples.Stage0Demo.health_check()
{:ok, "✓ System healthy: Bus and Registry running"}

# 2. Start a security agent
iex> {:ok, agent_pid} = Synapse.Examples.Stage0Demo.start_security_agent()
#PID<0.389.0>

# 3. Subscribe to results (in your terminal)
iex> Synapse.Examples.Stage0Demo.subscribe_to_results()
{:ok, "019a2deb-..."}

# 4. Send a review request
iex> Synapse.Examples.Stage0Demo.send_review_request("my_review_123")
{:ok, "my_review_123"}

# 5. Wait for and display the result
iex> Synapse.Examples.Stage0Demo.wait_for_result()
# See formatted output with findings!
```

### Option 3: Custom Review

```elixir
iex -S mix

# Start agent
{:ok, _pid} = Synapse.Examples.Stage0Demo.start_security_agent()

# Subscribe
Synapse.Examples.Stage0Demo.subscribe_to_results()

# Send YOUR code for review
{:ok, signal} = Jido.Signal.new(%{
  type: "review.request",
  source: "/your/app",
  data: %{
    review_id: "custom_001",
    diff: """
    + def unsafe_query(user_input) do
    +   "DELETE FROM users WHERE id = '\#{user_input}'"
    + end
    """,
    metadata: %{files: ["lib/dangerous.ex"]}
  }
})

Jido.Signal.Bus.publish(:synapse_bus, [signal])

# Wait for result
Synapse.Examples.Stage0Demo.wait_for_result()
```

## What You'll See

The agent will:
1. Receive your signal
2. Run 3 security checks (SQL injection, XSS, Auth)
3. Detect vulnerabilities
4. Emit a structured result

**Logger Output:**
```
[info] SecurityAgentServer started
[debug] SecurityAgent received signal
[notice] Executing Synapse.Actions.Security.CheckSQLInjection
[debug] SQL injection check completed
[info] SecurityAgent emitted result
```

**Result Structure:**
```elixir
%{
  review_id: "custom_001",
  agent: "security_specialist",
  confidence: 0.88,
  findings: [
    %{
      type: :sql_injection,
      severity: :high,
      file: "lib/dangerous.ex",
      summary: "Potential SQL injection detected",
      recommendation: "Use parameterized queries"
    }
  ],
  should_escalate: true,
  metadata: %{runtime_ms: 19, ...}
}
```

## Running Tests

```bash
# All tests (161 total)
mix test

# Just the working Stage 0 integration
mix test --only integration

# Watch it work
mix test test/synapse/agents/security_agent_server_test.exs
```

## What's Next

This is the **foundation**. Next stages build:
- **Stage 2**: CoordinatorAgent GenServer orchestrating multiple specialists
- **Stage 3**: PerformanceAgent GenServer
- **Stage 4**: Full multi-agent orchestration with directives
- **Stage 5**: Marketplace, negotiation, learning mesh

But right now? You have a **working autonomous agent** that reviews code via signals.

## Troubleshooting

**"Bus not accessible"**
```elixir
# Check if running
Supervisor.which_children(Synapse.Supervisor)
# Look for: {:synapse_bus, #PID<...>, :worker, [Jido.Signal.Bus]}
```

**"No result received"**
- Check agent is subscribed: Look for "SecurityAgentServer started" in logs
- Verify signal format matches `review.request` type
- Check timeout (default 2000ms)

**"Agent crashed"**
- Check logs for errors
- Verify diff format is string
- Ensure metadata is a map

## Architecture Deep Dive

See:
- [Stage 0 README](stage_0/README.md) - What was built
- [Stage 0 Backlog](stage_0/backlog.md) - Implementation tracking
- [Stage 1 README](stage_1/README.md) - Core components detail

## Code Quality

- **161 tests**, 0 failures
- Dialyzer clean
- mix format compliant
- Full precommit passing

---

**This is a real, working multi-agent system.** Start simple, then explore!
