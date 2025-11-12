# Troubleshooting Guide

## Common Issues and Solutions

### Signal.Bus Issues

#### "Bus not accessible" / `Process.whereis(:synapse_bus)` returns `nil`

**Cause**: Jido.Signal.Bus uses its own name registration, not Process registry.

**Solution**: Use the bus by name directly, don't rely on `Process.whereis/1`:

```elixir
# ✓ Correct
{:ok, sub_id} = Jido.Signal.Bus.subscribe(:synapse_bus, "pattern", ...)

# ✗ Won't work
pid = Process.whereis(:synapse_bus)  # Returns nil
```

**Verification**:
```elixir
# Check if bus is working
{:ok, _sub} = Jido.Signal.Bus.subscribe(:synapse_bus, "test", dispatch: {:pid, target: self()})
# If this works, bus is running
```

#### "No signals received"

**Symptoms**: Agent doesn't receive published signals.

**Checklist**:
1. Verify subscription pattern matches signal type:
   ```elixir
   # Subscribe
   Jido.Signal.Bus.subscribe(:synapse_bus, "review.request", ...)

   # Publish - type must match
   Jido.Signal.new(%{type: "review.request", ...})  # ✓
   Jido.Signal.new(%{type: "review-request", ...})  # ✗ No match
   ```

2. Check dispatch configuration:
   ```elixir
   # Async delivery (fire-and-forget)
   dispatch: {:pid, target: self(), delivery_mode: :async}

   # Sync delivery (blocks)
   dispatch: {:pid, target: self(), delivery_mode: :sync}
   ```

3. Verify process is alive:
   ```elixir
   pid = self()
   Process.alive?(pid)  # Must be true
   ```

4. Check message queue:
   ```elixir
   Process.info(self(), :messages)
   # Look for {:signal, %Jido.Signal{}}
   ```

#### "Signal published but no subscribers receive it"

**Cause**: Subscription happened after publish.

**Solution**: Subscribe before publishing:
```elixir
# 1. Subscribe first
{:ok, _sub} = Jido.Signal.Bus.subscribe(:synapse_bus, "event", ...)

# 2. Then publish
Jido.Signal.Bus.publish(:synapse_bus, [signal])
```

Or use replay for historical signals:
```elixir
{:ok, signals} = Jido.Signal.Bus.replay(
  :synapse_bus,
  "review.*",
  DateTime.utc_now() |> DateTime.add(-3600, :second)
)
```

### Agent Issues

#### "SecurityAgentServer won't start"

**Error**: `(UndefinedFunctionError) function Synapse.Agents.SecurityAgentServer.start_link/1 is undefined`

**Cause**: Module not compiled or not in load path.

**Solution**:
```bash
# Recompile
mix compile --force

# Verify module exists
iex -S mix
iex> Code.ensure_loaded?(Synapse.Agents.SecurityAgentServer)
true
```

#### "Agent started but doesn't process signals"

**Symptoms**: Agent starts, no errors, but no results.

**Debug Steps**:

1. Check subscription:
   ```elixir
   # In agent init, verify subscription succeeds
   {:ok, sub_id} = Jido.Signal.Bus.subscribe(bus, "review.request", ...)
   IO.inspect(sub_id, label: "Subscription ID")
   ```

2. Check signal format:
   ```elixir
   # Signal MUST have correct type
   signal.type  # Must be "review.request" exactly
   ```

3. Enable debug logging:
   ```elixir
   # config/dev.exs
   config :logger, level: :debug
   ```

4. Check handle_info is being called:
   ```elixir
   # Add to SecurityAgentServer.handle_info
   def handle_info(msg, state) do
     IO.inspect(msg, label: "Received message")
     # ... rest of implementation
   end
   ```

#### "Agent receives signal but crashes"

**Common Causes**:

1. **Missing data fields**:
   ```elixir
   # ✓ Include all required fields
   data: %{
     review_id: "...",    # Required
     diff: "...",         # Required
     metadata: %{}        # Can be empty but must exist
   }
   ```

2. **Invalid diff format**:
   ```elixir
   # ✓ Must be string
   diff: "actual diff content"

   # ✗ Don't pass other types
   diff: %{content: "..."}  # Will crash
   ```

3. **Action execution errors**:
   ```bash
   # Check logs for action failures
   grep "Executing.*Check" log/dev.log
   grep "error" log/dev.log
   ```

### Test Issues

#### "Integration tests fail intermittently"

**Cause**: Timing issues with async signal delivery.

**Solution**: Use longer timeouts or sync delivery mode:

```elixir
# Increase timeout
assert_receive {:signal, result}, 3000  # Was 1000

# Or use sync dispatch in tests
dispatch: {:pid, target: self(), delivery_mode: :sync}
```

#### "Tests pass individually but fail when run together"

**Cause**: Shared state in Signal.Bus or Registry.

**Solution**: Mark integration tests as `async: false`:

```elixir
defmodule MyIntegrationTest do
  use ExUnit.Case, async: false  # Important!

  @moduletag :integration
  # ...
end
```

#### "`mix test` hangs"

**Cause**: Agent process not terminating.

**Solution**: Add cleanup in test setup:

```elixir
setup do
  {:ok, pid} = SecurityAgentServer.start_link(...)

  on_exit(fn ->
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end
  end)

  %{agent_pid: pid}
end
```

### Action Issues

#### "CheckSQLInjection returns empty findings for obvious SQL injection"

**Cause**: Pattern not matching.

**Debug**:
```elixir
params = %{
  diff: your_diff,
  files: ["lib/repo.ex"],
  metadata: %{}
}

{:ok, result} = Jido.Exec.run(CheckSQLInjection, params, %{})

IO.inspect(result.findings, label: "Findings")
IO.inspect(params.diff, label: "Diff analyzed")
```

**Common Pattern Issues**:
- Diff must include `+` prefix for added lines
- SQL keywords must be in the diff
- String interpolation `#{}` must be present

#### "Action times out"

**Cause**: Default 30s timeout exceeded.

**Solution**: Increase timeout:
```elixir
{:ok, result} = Jido.Exec.run(
  MyAction,
  params,
  context,
  timeout: 60_000  # 60 seconds
)
```

### Performance Issues

#### "Agent is slow to respond"

**Symptoms**: Results take > 1 second.

**Debug**:
```elixir
# Check metadata.runtime_ms in result
result_signal.data.metadata.runtime_ms  # Should be < 100ms typically
```

**Common Causes**:
1. Large diff (> 10,000 lines)
2. Complex regex matching
3. Multiple subscribers slowing bus

**Solutions**:
- Batch large diffs
- Use diff sampling for very large changes
- Profile action execution: `:timer.tc(fn -> CheckSQLInjection.run(...) end)`

#### "Memory usage growing over time"

**Cause**: Review history not capped properly.

**Check**:
```elixir
# Agent state should cap collections
:sys.get_state(agent_pid)
|> get_in([:agent, :state, :review_history])
|> length()
# Should be <= 100

:sys.get_state(agent_pid)
|> get_in([:agent, :state, :scar_tissue])
|> length()
# Should be <= 50
```

**Verify**: Look at `SecurityAgent.record_history/2` - should use `Enum.take(..., 100)`.

### Development Issues

#### "Changes not reflected in iex"

**Cause**: Code not recompiled.

**Solution**:
```elixir
# In iex
iex> recompile()

# Or restart
iex> System.stop()  # Ctrl+C twice
$ iex -S mix
```

#### "Tests fail after changing signal schema"

**Cause**: Cached test data doesn't match new schema.

**Solution**:
```bash
# Clean and recompile
mix clean
mix compile
mix test
```

## Debugging Techniques

### Enable Debug Logging

```elixir
# config/dev.exs
config :logger,
  level: :debug,
  backends: [:console]

# Or at runtime
Logger.configure(level: :debug)
```

### Trace Signal Flow

```elixir
# Subscribe and log all signals
{:ok, _} = Jido.Signal.Bus.subscribe(
  :synapse_bus,
  "**",  # All signals
  dispatch: {:logger, level: :info, structured: true}
)
```

### Inspect Agent State

```elixir
# Get current state
agent_pid = # your agent PID
state = :sys.get_state(agent_pid)

IO.inspect(state.agent.state, label: "Agent State")
```

### Replay Signal History

```elixir
# See what signals were published
{:ok, signals} = Jido.Signal.Bus.replay(
  :synapse_bus,
  "review.**",
  DateTime.utc_now() |> DateTime.add(-3600, :second),  # Last hour
  limit: 100
)

Enum.each(signals, fn sig ->
  IO.puts("#{sig.type} - #{sig.id}")
end)
```

### Monitor Telemetry

```elixir
# Attach telemetry handler
:telemetry.attach(
  "debug-handler",
  [:jido, :exec, :stop],
  fn _event, measurements, metadata, _config ->
    IO.puts("Action #{metadata.action} took #{measurements.duration}μs")
  end,
  nil
)
```

## Getting Help

### Check System Health

```elixir
iex> Synapse.Examples.Stage0Demo.health_check()
{:ok, "✓ System healthy: Bus and Registry running"}
```

### Run the Demo

```elixir
iex> Synapse.Examples.Stage0Demo.run()
# If this works, system is functioning correctly
```

### Verify Supervision Tree

```elixir
iex> Supervisor.which_children(Synapse.Supervisor)
# Should show :synapse_bus and Synapse.AgentRegistry
```

### Check Test Suite

```bash
# Run all tests
mix test

# Run integration only
mix test --only integration

# Run precommit (full quality check)
mix precommit
```

## Still Stuck?

1. Check logs: `tail -f log/dev.log`
2. Run demo: `Synapse.Examples.Stage0Demo.run()`
3. Check docs: `docs/20251028/multi_agent_framework/`
4. Review tests: Examples in `test/synapse/agents/security_agent_server_test.exs`

## Known Limitations

- Single agent type (SecurityAgent) has GenServer - others in Stage 2
- No coordinator orchestration yet - Stage 2
- No directive processing (Spawn, Enqueue) - Stage 2
- In-memory state only - persistence in Stage 3
- Single node only - distribution in Stage 4

These are **intentional staging decisions**, not bugs.
