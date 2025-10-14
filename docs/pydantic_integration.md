# Pydantic-AI Integration

## Overview

The Synapse framework provides a robust integration with `pydantic-ai` through a clean, type-safe interface. This integration leverages Elixir's powerful OTP principles for managing Python-based AI agents while maintaining the flexibility and ease of use that `pydantic-ai` provides.

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/your-org/synapse.git
cd synapse
```

2. Run the setup script:
```bash
mix run setup.exs
```

3. Start the application:
```bash
iex -S mix
```

That's it! The setup script automatically handles:
- Checking system requirements
- Setting up Python virtual environment
- Installing Python dependencies
- Installing Elixir dependencies
- Compiling the project

## Architecture

The integration consists of several key components:

1. **Agent Process** (`PydanticAgentProcess`)
   - Manages the lifecycle of individual agents
   - Handles message passing between Elixir and Python
   - Provides streaming capabilities
   - Manages state and error handling

2. **HTTP Client** (`PydanticHTTPClient`)
   - Handles communication with Python agents
   - Supports both synchronous and streaming requests
   - Built on Finch for better performance
   - Implements proper connection pooling

3. **Tool Registry** (`PydanticToolRegistry`)
   - Manages available tools for agents
   - Validates tool configurations
   - Handles tool execution
   - Provides a clean interface for tool registration

4. **Supervisor** (`PydanticSupervisor`)
   - Manages component lifecycles
   - Provides fault tolerance
   - Handles dynamic agent creation/deletion
   - Monitors system health

## Usage

### Basic Setup

```elixir
# Configuration
config = %{
  name: "my_agent",
  python_module: "translation_agent",
  model: "gemini-1.5-pro",
  system_prompt: "You are a helpful assistant."
}

# Start the agent
{:ok, pid} = SynapseCore.PydanticSupervisor.start_agent(config)

# Use the agent
{:ok, result} = SynapseCore.PydanticAgentProcess.run(
  "my_agent",
  "Translate 'Hello' to Spanish"
)
```

### Running an Agent

```elixir
# Synchronous execution
{:ok, result} = SynapseCore.PydanticAgentProcess.run(
  "my_agent",
  "Hello, how are you?",
  [], # message history
  %{} # model settings
)

# Streaming execution
{:ok, stream_pid} = SynapseCore.PydanticAgentProcess.run_stream(
  "my_agent",
  "Tell me a long story."
)

# Receive streamed chunks
receive do
  {:chunk, chunk} -> IO.puts(chunk)
  {:end_stream} -> IO.puts("Done!")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

### Tool Registration and Usage

```elixir
# Register a tool
:ok = SynapseCore.PydanticToolRegistry.register_tool(%{
  name: "my_tool",
  description: "Does something useful",
  parameters: %{
    "type" => "object",
    "properties" => %{
      "input" => %{"type" => "string"}
    },
    "required" => ["input"]
  },
  handler: fn %{"input" => input} -> 
    # Tool implementation
    "Processed: #{input}"
  end
})

# Call a tool
{:ok, result} = SynapseCore.PydanticAgentProcess.call_tool(
  "my_agent",
  "my_tool",
  %{"input" => "test"}
)
```

## Error Handling

Synapse provides comprehensive error handling through structured error types:

### Environment Errors

```elixir
# Example environment error
%SynapseCore.Error.PythonEnvError{
  message: "Python version mismatch",
  reason: :version_mismatch,
  context: %{
    found: "3.8.0",
    required: "3.10.0"
  }
}
```

### Agent Errors

```elixir
# Example agent error
%SynapseCore.Error.AgentError{
  message: "Agent execution failed",
  reason: :execution_failed,
  context: %{
    error: "Memory limit exceeded"
  }
}
```

### HTTP Errors

```elixir
# Example HTTP error
%SynapseCore.Error.HTTPError{
  message: "Failed to connect to Python service",
  reason: :connection_failed,
  context: %{
    error: "Connection refused"
  }
}
```

### Tool Errors

```elixir
# Example tool error
%SynapseCore.Error.ToolError{
  message: "Tool parameter validation failed",
  reason: :validation_failed,
  context: %{
    error: "Missing required parameter: input"
  }
}
```

## Troubleshooting Guide

### Setup Issues

1. **Python Version Error**
   ```
   ❌ Python Environment Error:
   Python version mismatch. Found: 3.8.0, Required: 3.10.0
   ```
   **Solution**: Install Python 3.10 or higher:
   ```bash
   sudo apt update
   sudo apt install python3.10
   ```

2. **Virtual Environment Error**
   ```
   ❌ Python Environment Error:
   Failed to create virtual environment
   ```
   **Solution**: Install python3-venv:
   ```bash
   sudo apt install python3-venv
   ```

3. **Dependency Installation Error**
   ```
   ❌ Python Environment Error:
   Failed to install dependencies
   ```
   **Solution**: 
   - Check internet connection
   - Verify pip is working: `python3 -m pip --version`
   - Try manually: `python3 -m pip install poetry`

### Runtime Issues

1. **Agent Start Failed**
   ```
   ❌ Agent Error:
   Failed to start agent: Port already in use
   ```
   **Solution**:
   - Check for running processes: `lsof -i :8000`
   - Kill conflicting process: `kill -9 <PID>`

2. **HTTP Connection Error**
   ```
   ❌ HTTP Error:
   Failed to connect to Python service
   ```
   **Solution**:
   - Verify Python service is running
   - Check logs: `_build/dev/lib/synapse_core/priv/python/.venv/logs/`
   - Restart the application

3. **Tool Execution Error**
   ```
   ❌ Tool Error:
   Tool execution failed: Memory limit exceeded
   ```
   **Solution**:
   - Check system resources
   - Adjust memory limits in config
   - Break task into smaller chunks

## Advanced Troubleshooting Scenarios

### Network Issues

1. **Port Conflicts**
   ```
   ❌ HTTP Error:
   Failed to bind to port 8000: Address already in use
   ```
   **Solution**:
   ```bash
   # Find process using port
   sudo lsof -i :8000
   # Kill process
   sudo kill -9 <PID>
   # Or change port in config
   config :synapse_core, :http_port, 8001
   ```

2. **Firewall Blocks**
   ```
   ❌ HTTP Error:
   Connection timed out after 5000ms
   ```
   **Solution**:
   ```bash
   # Check firewall status
   sudo ufw status
   # Allow port if needed
   sudo ufw allow 8000/tcp
   ```

3. **DNS Resolution**
   ```
   ❌ HTTP Error:
   Failed to resolve hostname: python_service
   ```
   **Solution**:
   - Check /etc/hosts entries
   - Verify DNS settings
   - Use IP address instead of hostname

### Python Environment Issues

1. **Poetry Lock Conflicts**
   ```
   ❌ Python Environment Error:
   Failed to install dependencies: Lockfile hash doesn't match
   ```
   **Solution**:
   ```bash
   # Remove lock file
   rm poetry.lock
   # Regenerate lock file
   poetry lock
   # Reinstall dependencies
   poetry install
   ```

2. **Corrupted Virtual Environment**
   ```
   ❌ Python Environment Error:
   ImportError: No module named 'venv'
   ```
   **Solution**:
   ```bash
   # Remove corrupted venv
   rm -rf .venv
   # Recreate venv
   python3 -m venv .venv
   # Reinstall dependencies
   poetry install
   ```

3. **SSL Certificate Issues**
   ```
   ❌ Python Environment Error:
   SSL: CERTIFICATE_VERIFY_FAILED
   ```
   **Solution**:
   ```bash
   # Update certificates
   sudo apt-get install ca-certificates
   # Or disable SSL verification (not recommended for production)
   export PYTHONHTTPSVERIFY=0
   ```

### Memory and Resource Issues

1. **Memory Exhaustion**
   ```
   ❌ Agent Error:
   MemoryError: Unable to allocate array
   ```
   **Solution**:
   - Check system memory: `free -h`
   - Adjust memory limits:
   ```elixir
   config :synapse_core, :memory_limit, "4G"
   ```
   - Enable swap if needed:
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

2. **CPU Throttling**
   ```
   ❌ Agent Error:
   Execution time exceeded limit: 30s
   ```
   **Solution**:
   - Check CPU usage: `top`
   - Adjust timeouts:
   ```elixir
   config :synapse_core, :execution_timeout, 60_000
   ```
   - Consider process nice values:
   ```bash
   sudo renice -n -10 -p $(pgrep beam.smp)
   ```

3. **Disk Space**
   ```
   ❌ Python Environment Error:
   No space left on device
   ```
   **Solution**:
   - Check disk usage: `df -h`
   - Clean old logs:
   ```bash
   find _build/dev/lib/synapse_core/log -mtime +7 -delete
   ```
   - Rotate logs:
   ```elixir
   config :logger,
     rotate: [max_bytes: 10_485_760, keep: 5]
   ```

### Process and State Issues

1. **Zombie Processes**
   ```
   ❌ Agent Error:
   Process <0.123.0> not responding
   ```
   **Solution**:
   ```elixir
   # In iex
   Process.whereis(:stuck_agent) |> Process.exit(:kill)
   ```

2. **State Corruption**
   ```
   ❌ Agent Error:
   Invalid state: Expected map, got nil
   ```
   **Solution**:
   ```elixir
   # Reset agent state
   SynapseCore.PydanticAgentProcess.reset_state("agent_name")
   ```

3. **Deadlocks**
   ```
   ❌ Agent Error:
   Timeout waiting for resource lock
   ```
   **Solution**:
   - Check process message queues:
   ```elixir
   Process.info(pid, :message_queue_len)
   ```
   - Force release locks:
   ```elixir
   SynapseCore.PydanticAgentProcess.force_unlock("agent_name")
   ```

### Integration Issues

1. **Version Mismatches**
   ```
   ❌ Tool Error:
   API version mismatch: Expected 2.0, got 1.0
   ```
   **Solution**:
   - Check versions:
   ```elixir
   SynapseCore.version()
   SynapseCore.PythonEnvManager.get_package_version("pydantic")
   ```
   - Update dependencies:
   ```bash
   mix deps.update --all
   poetry update
   ```

2. **Encoding Problems**
   ```
   ❌ HTTP Error:
   Invalid UTF-8 byte sequence
   ```
   **Solution**:
   ```elixir
   # Force encoding
   config :synapse_core, :force_encoding, "UTF-8"
   ```

3. **Schema Validation**
   ```
   ❌ Tool Error:
   Invalid schema: Additional properties not allowed
   ```
   **Solution**:
   - Debug schema:
   ```elixir
   SynapseCore.PydanticToolRegistry.debug_schema("tool_name")
   ```
   - Update schema:
   ```elixir
   SynapseCore.PydanticToolRegistry.update_schema("tool_name", schema)
   ```

## Best Practices

1. **Error Handling**
   - Always handle both Elixir and Python errors appropriately
   - Use structured error types
   - Implement proper retry logic

2. **State Management**
   - Keep agent state minimal
   - Use message passing for communication
   - Implement proper cleanup

3. **Performance**
   - Use streaming for long-running operations
   - Implement proper connection pooling
   - Monitor resource usage

4. **Testing**
   - Write comprehensive tests for both Elixir and Python components
   - Use proper mocking for external services
   - Test error conditions

## Monitoring and Debugging

The integration provides several tools for monitoring and debugging:

1. **Status Checks**
```elixir
# Get system status
status = SynapseCore.PydanticSupervisor.status()

# List running agents
agents = SynapseCore.PydanticSupervisor.list_agents()
```

2. **Logging**
   - All components use structured logging
   - Log levels can be configured
   - Integration with existing logging systems

3. **Metrics**
   - Request/response times
   - Error rates
   - Resource usage

## Configuration

The integration can be configured through application config:

```elixir
# config/config.exs
config :synapse_core, :pydantic,
  http_client: [
    pool_size: 50,
    connect_timeout: 5_000,
    receive_timeout: 30_000
  ],
  tool_registry: [
    max_tools: 100
  ]
```

## Limitations and Considerations

1. **Network Dependencies**
   - Requires reliable communication between Elixir and Python
   - Consider timeouts and retries

2. **Resource Management**
   - Monitor memory usage of Python processes
   - Implement proper cleanup

3. **Security**
   - Validate all inputs
   - Consider sandboxing Python execution
   - Implement proper authentication

## Future Improvements

1. **Enhanced Tool Support**
   - Better tool discovery
   - More sophisticated parameter validation
   - Tool versioning

2. **Performance Optimizations**
   - gRPC support
   - Better connection pooling
   - Caching mechanisms

3. **Developer Experience**
   - Better debugging tools
   - More example agents
   - Enhanced documentation

## Logging and Debugging

1. **Error Logging**
   ```elixir
   # Log with context
   SynapseCore.Error.log_error(error, severity: :error, include_stacktrace: true)
   ```

2. **Error Formatting**
   ```elixir
   # Format for display
   SynapseCore.Error.format_error(error, include_stacktrace: false)
   ```

3. **Log Locations**
   - Elixir logs: `_build/dev/lib/synapse_core/log/`
   - Python logs: `_build/dev/lib/synapse_core/priv/python/.venv/logs/`
   - HTTP logs: `_build/dev/lib/synapse_core/log/http.log`
