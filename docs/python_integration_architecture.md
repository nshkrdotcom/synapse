# Axon Python Integration Architecture

## Overview

This document details the architecture of Axon's Python integration, focusing on how we manage Python environments, execute Python code, and handle communication between Elixir and Python processes. This integration is designed to provide robust, fault-tolerant execution of Python-based AI agents while leveraging BEAM/OTP's supervision and process isolation capabilities.

## Core Components

### 1. Python Environment Management

#### PythonEnvManager (Elixir)
- Located in `apps/axon_core/lib/axon_core/python_env_manager.ex`
- Responsible for:
  - Validating Python installation (version >= 3.10)
  - Creating and managing virtual environments
  - Installing required Python packages
  - Handling environment-specific errors via custom `PythonEnvError`
- Uses pattern matching and error tuples for robust error handling
- Implements idempotent operations for environment setup

```elixir
defmodule AxonCore.PythonEnvManager do
  def ensure_env! do
    case check_python_env() do
      :ok -> :ok
      {:error, reason, context} -> raise PythonEnvError.new(reason, context)
    end
  end
end
```

### 2. Agent Process Management

#### Agent Supervisor (Elixir)
- Located in `lib/axon/agent.ex`
- Implements OTP Supervisor behavior
- Manages lifecycle of agent processes
- Handles dynamic agent creation and termination
- Uses process groups (`:pg`) for agent discovery
- Child specification:
  ```elixir
  %{
    id: agent_name,
    start: {Axon.Agent, :start_link, [opts]},
    type: :supervisor
  }
  ```

#### Agent Server (Elixir)
- Located in `lib/axon/agent/server.ex`
- Implements GenServer behavior
- Manages individual agent state
- Handles:
  - Port-based communication with Python processes
  - HTTP-based communication with Python agent servers
  - Message routing and response handling
- Uses Finch for HTTP communication
- Implements automatic port assignment and process monitoring

### 3. Python-Elixir Communication

#### Port Communication
- Uses Erlang ports for process spawning and IO streaming
- Implemented in `Axon.Agent.Server`:
  ```elixir
  Port.open({:spawn_executable, cmd}, [
    {:args, [module, port, model]},
    {:cd, python_path},
    {:env, environment_vars},
    :binary,
    :use_stdio,
    :stderr_to_stdout,
    :hide
  ])
  ```

#### HTTP Communication
- Python agents expose HTTP endpoints
- Elixir uses Finch for HTTP client functionality
- Protocol:
  - POST /agents/{agent_id}/run_sync - Synchronous execution
  - POST /agents/{agent_id}/run_stream - Streaming execution
- Response formats:
  ```json
  {
    "result": Object,
    "messages": Array,
    "usage": Object
  }
  ```

### 4. Python Agent Implementation

#### Agent Wrapper (Python)
- Located in `apps/axon_python/src/axon_python/agent_wrapper.py`
- Implements:
  - FastAPI HTTP server
  - Agent lifecycle management
  - Message handling and routing
  - Error handling and reporting
- Features:
  - Automatic port binding
  - Signal handling for graceful shutdown
  - Structured logging
  - Error propagation to Elixir

## Supervision Strategy

```
Axon.Supervisor
├── Axon.Telemetry
├── Phoenix.PubSub
└── Axon.Agent (for each agent)
    ├── Task.Supervisor
    └── Axon.Agent.Server
        └── Port (Python Process)
```

- Top-level supervisor uses `:one_for_one` strategy
- Agent supervisors handle their own Python processes
- Task supervisor manages async operations

## Error Handling and Recovery

1. Python Process Crashes
   - Detected via Port monitoring
   - Server initiates restart with backoff
   - Supervisor maintains overall system stability

2. Network Communication Errors
   - HTTP client implements retry logic
   - Timeouts are configurable per request type
   - Errors are logged and propagated appropriately

3. Environment Setup Failures
   - Custom error types for clear failure reporting
   - Automatic cleanup of partial states
   - Detailed context for debugging

## Testing Strategy

1. Unit Tests
   - Mock Port communication
   - Test supervisor behavior
   - Verify error handling

2. Integration Tests
   - End-to-end agent communication
   - Python environment setup
   - HTTP endpoint functionality

3. Property-Based Tests
   - Message format validation
   - State transition verification
   - Concurrency behavior

## Initial HTTP Integration Test

For the basic end-to-end test:

1. Start the system:
   ```elixir
   {:ok, _} = Application.ensure_all_started(:axon)
   ```

2. Create an agent:
   ```elixir
   {:ok, agent} = Axon.Agent.start_link(
     name: "test_agent",
     python_module: "agents.example_agent",
     model: "test:model",
     port: 5000
   )
   ```

3. Send a test message:
   ```elixir
   {:ok, response} = Axon.Agent.Server.send_message(
     "test_agent",
     %{
       "prompt" => "Hello, agent!",
       "message_history" => []
     }
   )
   ```

4. Verify response structure:
   ```elixir
   assert %{
     "result" => _,
     "messages" => messages,
     "usage" => %{"total_tokens" => _}
   } = response
   ```

## Future Considerations

1. Scaling
   - Agent pool management
   - Load balancing across Python processes
   - Resource usage monitoring

2. Security
   - Process isolation improvements
   - Input validation
   - Resource limits

3. Monitoring
   - Detailed metrics collection
   - Performance tracking
   - Error rate monitoring

4. Deployment
   - Container support
   - Environment configuration
   - Health checks
