# PydanticAgentProcess

## Overview

`PydanticAgentProcess` is the core component that manages individual AI agents in the Axon framework. It handles the complete lifecycle of an agent, from initialization to shutdown, and manages all communication between Elixir and the Python-based pydantic-ai agent.

## Architecture

The process is implemented as a GenServer with the following responsibilities:

1. **Lifecycle Management**
   - Agent initialization
   - State management
   - Graceful shutdown
   - Error recovery

2. **Message Handling**
   - Synchronous message processing
   - Streaming support
   - Tool calling
   - Error handling

3. **State Management**
   - Message history
   - Model settings
   - Configuration

## Usage

### Starting an Agent

```elixir
config = %{
  name: "my_agent",
  python_module: "my_module",
  model: "gemini-1.5-pro",
  port: 8000,
  system_prompt: "You are a helpful assistant.",
  tools: [
    %{
      name: "my_tool",
      description: "Does something useful",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "input" => %{"type" => "string"}
        }
      }
    }
  ],
  result_type: %{
    "type" => "object",
    "properties" => %{
      "response" => %{"type" => "string"}
    }
  }
}

{:ok, pid} = AxonCore.PydanticAgentProcess.start_link(config)
```

### Running Commands

```elixir
# Synchronous execution
{:ok, result} = AxonCore.PydanticAgentProcess.run(
  "my_agent",
  "Hello!",
  [], # message history
  %{} # model settings
)

# Streaming execution
{:ok, stream_pid} = AxonCore.PydanticAgentProcess.run_stream(
  "my_agent",
  "Tell me a story."
)

# Tool calling
{:ok, result} = AxonCore.PydanticAgentProcess.call_tool(
  "my_agent",
  "my_tool",
  %{"input" => "test"}
)
```

## Error Handling

The process implements comprehensive error handling:

1. **Network Errors**
   ```elixir
   {:error, :network_error, reason}
   ```

2. **Agent Errors**
   ```elixir
   {:error, :agent_error, reason}
   ```

3. **Tool Errors**
   ```elixir
   {:error, :tool_error, reason}
   ```

4. **Validation Errors**
   ```elixir
   {:error, :validation_error, reason}
   ```

## State Management

The process maintains the following state:

```elixir
%{
  name: String.t(),           # Agent name
  python_module: String.t(),  # Python module path
  model: String.t(),         # Model identifier
  port: integer(),           # Port number
  base_url: String.t(),      # Base URL for HTTP requests
  message_history: list(),   # Message history
  model_settings: map(),     # Model-specific settings
  system_prompt: String.t(), # System prompt
  tools: list(),            # Available tools
  result_type: map(),       # Expected result type
  extra_env: keyword()      # Additional environment variables
}
```

## Configuration

The process can be configured through application config:

```elixir
config :axon_core, :pydantic_agent,
  default_timeout: 60_000,
  retry_attempts: 3,
  retry_delay: 1000
```

## Monitoring

The process emits telemetry events for monitoring:

```elixir
[:axon, :agent, :request, :start]
[:axon, :agent, :request, :stop]
[:axon, :agent, :request, :exception]
```

## Best Practices

1. **Resource Management**
   - Always handle process termination properly
   - Clean up resources in terminate callback
   - Monitor long-running operations

2. **Error Handling**
   - Implement proper retry logic
   - Log errors appropriately
   - Provide meaningful error messages

3. **State Management**
   - Keep state minimal
   - Handle state updates atomically
   - Implement proper cleanup

4. **Testing**
   - Mock HTTP responses
   - Test error conditions
   - Verify state transitions

## Common Issues and Solutions

1. **Agent Not Responding**
   - Check network connectivity
   - Verify Python process is running
   - Check port availability

2. **Memory Issues**
   - Monitor message history size
   - Implement proper cleanup
   - Use streaming for large responses

3. **Performance Issues**
   - Use appropriate timeouts
   - Implement proper retry logic
   - Monitor resource usage

## Integration Points

1. **HTTP Client**
   - Uses `PydanticHTTPClient` for communication
   - Handles both sync and streaming requests
   - Manages connection pooling

2. **Tool Registry**
   - Integrates with `PydanticToolRegistry`
   - Validates tool configurations
   - Manages tool execution

3. **Supervisor**
   - Managed by `PydanticSupervisor`
   - Handles process lifecycle
   - Implements fault tolerance
