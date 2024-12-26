# PydanticToolRegistry

## Overview

`PydanticToolRegistry` is a central registry for managing and executing tools that can be used by pydantic-ai agents. It provides tool validation, registration, and execution capabilities while ensuring type safety and proper error handling.

## Features

1. **Tool Management**
   - Registration and validation
   - Tool discovery
   - Execution handling

2. **Type Safety**
   - JSON Schema validation
   - Parameter checking
   - Result validation

3. **Error Handling**
   - Validation errors
   - Execution errors
   - Resource cleanup

## Usage

### Basic Setup

```elixir
# Add to your supervision tree
children = [
  AxonCore.PydanticToolRegistry
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Tool Registration

```elixir
# Register a simple tool
:ok = AxonCore.PydanticToolRegistry.register_tool(%{
  name: "greet",
  description: "Greets a person",
  parameters: %{
    "type" => "object",
    "properties" => %{
      "name" => %{"type" => "string"}
    },
    "required" => ["name"]
  },
  handler: fn %{"name" => name} -> "Hello, #{name}!" end
})

# Register a module-based tool
:ok = AxonCore.PydanticToolRegistry.register_tool(%{
  name: "fetch_data",
  description: "Fetches data from a source",
  parameters: %{
    "type" => "object",
    "properties" => %{
      "source" => %{"type" => "string"},
      "id" => %{"type" => "integer"}
    },
    "required" => ["source", "id"]
  },
  handler: {MyApp.DataFetcher, :fetch}
})
```

### Tool Execution

```elixir
# Execute a tool
{:ok, result} = AxonCore.PydanticToolRegistry.execute_tool(
  "greet",
  %{"name" => "Alice"}
)

# List available tools
tools = AxonCore.PydanticToolRegistry.list_tools()

# Get tool information
{:ok, tool} = AxonCore.PydanticToolRegistry.get_tool("greet")
```

## Tool Configuration

Tools are configured with a standardized structure:

```elixir
%{
  name: String.t(),          # Tool name
  description: String.t(),   # Tool description
  parameters: map(),         # JSON Schema for parameters
  handler: {module, atom} | function()  # Tool implementation
}
```

## Parameter Validation

The registry implements JSON Schema validation:

```elixir
defp validate_parameters_schema(schema) do
  required_keys = ["type", "properties"]
  case validate_required_keys(schema, required_keys) do
    :ok -> :ok
    error -> {:error, {:invalid_schema, error}}
  end
end
```

## Error Handling

The registry provides detailed error information:

1. **Validation Errors**
   ```elixir
   {:error, :validation_error, details}
   ```

2. **Execution Errors**
   ```elixir
   {:error, :execution_error, reason}
   ```

3. **Not Found Errors**
   ```elixir
   {:error, :tool_not_found}
   ```

## Best Practices

1. **Tool Design**
   - Keep tools focused and simple
   - Provide clear descriptions
   - Use proper parameter validation

2. **Error Handling**
   - Implement proper validation
   - Handle all error cases
   - Provide meaningful messages

3. **Performance**
   - Keep tool execution fast
   - Implement timeouts
   - Monitor resource usage

## Monitoring

The registry emits telemetry events:

```elixir
[:axon, :tool, :execute, :start]
[:axon, :tool, :execute, :stop]
[:axon, :tool, :execute, :exception]
```

## Common Issues and Solutions

1. **Invalid Tool Configuration**
   - Validate all parameters
   - Check handler existence
   - Verify schema correctness

2. **Execution Failures**
   - Implement proper error handling
   - Add logging
   - Monitor execution time

3. **Resource Management**
   - Clean up after execution
   - Monitor memory usage
   - Implement timeouts

## Integration Points

1. **Agent Process**
   - Used by `PydanticAgentProcess`
   - Provides tool execution
   - Handles validation

2. **JSON Codec**
   - Uses `PydanticJSONCodec`
   - Validates parameters
   - Handles results

3. **Supervisor**
   - Managed by `PydanticSupervisor`
   - Handles process lifecycle
   - Implements fault tolerance

## Advanced Usage

### Custom Tool Handlers

```elixir
# Async tool handler
defmodule MyApp.AsyncTool do
  def handle(args) do
    Task.async(fn ->
      # Long running operation
      Process.sleep(1000)
      {:ok, "Result: #{inspect(args)}"}
    end)
    |> Task.await()
  end
end

# Register async tool
:ok = AxonCore.PydanticToolRegistry.register_tool(%{
  name: "async_tool",
  description: "An async tool",
  parameters: %{
    "type" => "object",
    "properties" => %{
      "input" => %{"type" => "string"}
    }
  },
  handler: {MyApp.AsyncTool, :handle}
})
```

### Tool Composition

```elixir
# Compose multiple tools
defmodule MyApp.ComposedTool do
  def handle(%{"steps" => steps}) do
    steps
    |> Enum.reduce_while({:ok, nil}, fn step, {:ok, acc} ->
      case AxonCore.PydanticToolRegistry.execute_tool(
        step["tool"],
        Map.put(step["args"], "_previous", acc)
      ) do
        {:ok, result} -> {:cont, {:ok, result}}
        error -> {:halt, error}
      end
    end)
  end
end
```
