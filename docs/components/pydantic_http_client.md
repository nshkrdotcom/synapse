# PydanticHTTPClient

## Overview

`PydanticHTTPClient` is a specialized HTTP client built on top of Finch for communicating with Python-based pydantic-ai agents. It provides optimized performance, connection pooling, and support for both synchronous and streaming requests.

## Features

1. **Performance Optimization**
   - Connection pooling
   - Keep-alive connections
   - Proper timeout handling

2. **Request Types**
   - Synchronous POST requests
   - Server-Sent Events (SSE) streaming
   - JSON encoding/decoding

3. **Error Handling**
   - Network error recovery
   - Timeout handling
   - Proper cleanup

## Usage

### Basic Setup

```elixir
# Add to your supervision tree
children = [
  SynapseCore.PydanticHTTPClient
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Making Requests

```elixir
# Synchronous POST request
{:ok, response} = SynapseCore.PydanticHTTPClient.post(
  "http://localhost:8000/run",
  %{prompt: "Hello!"}
)

# Streaming request
{:ok, stream_pid} = SynapseCore.PydanticHTTPClient.post_stream(
  "http://localhost:8000/stream",
  %{prompt: "Tell me a story."}
)

# Handle streaming response
receive do
  {:chunk, chunk} -> IO.puts(chunk)
  {:end_stream} -> IO.puts("Done!")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

## Configuration

The client can be configured through application config:

```elixir
config :synapse_core, :pydantic_http_client,
  pool_size: 50,
  connect_timeout: 5_000,
  receive_timeout: 30_000,
  max_retries: 3,
  retry_delay: 1000
```

## Connection Pool Management

The client uses Finch's connection pooling:

```elixir
def child_spec(_opts) do
  children = [
    {Finch, name: __MODULE__, pools: %{
      default: [size: @pool_size, count: 1]
    }}
  ]

  %{
    id: __MODULE__,
    type: :supervisor,
    start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
  }
end
```

## Error Handling

The client implements comprehensive error handling:

1. **Network Errors**
   ```elixir
   {:error, :network_error, reason}
   ```

2. **Timeout Errors**
   ```elixir
   {:error, :timeout, duration}
   ```

3. **HTTP Errors**
   ```elixir
   {:error, :http_error, status, body}
   ```

## Streaming Implementation

The client uses a dedicated process for handling SSE streams:

```elixir
defp stream_request(url, headers, body) do
  req = Finch.build(:post, url, headers, body)
  case Finch.stream(req, __MODULE__, self(), []) do
    {:ok, conn_ref} -> handle_stream(conn_ref)
    {:error, reason} -> {:error, reason}
  end
end
```

## Best Practices

1. **Resource Management**
   - Monitor connection pool usage
   - Implement proper timeouts
   - Clean up resources properly

2. **Error Handling**
   - Implement proper retry logic
   - Log errors appropriately
   - Handle all error cases

3. **Performance**
   - Use appropriate pool sizes
   - Monitor connection usage
   - Implement proper timeouts

## Monitoring

The client emits telemetry events:

```elixir
[:synapse, :http, :request, :start]
[:synapse, :http, :request, :stop]
[:synapse, :http, :request, :exception]
```

## Common Issues and Solutions

1. **Connection Pool Exhaustion**
   - Monitor pool usage
   - Adjust pool size
   - Implement backpressure

2. **Timeouts**
   - Adjust timeout settings
   - Implement retry logic
   - Monitor long-running requests

3. **Memory Leaks**
   - Properly close connections
   - Monitor stream processes
   - Implement timeouts

## Integration Points

1. **Agent Process**
   - Used by `PydanticAgentProcess`
   - Handles all HTTP communication
   - Manages connection lifecycle

2. **JSON Codec**
   - Uses `PydanticJSONCodec`
   - Handles serialization
   - Manages encoding/decoding

3. **Supervisor**
   - Managed by `PydanticSupervisor`
   - Handles process lifecycle
   - Implements fault tolerance
