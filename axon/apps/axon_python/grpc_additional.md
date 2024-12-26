**1. gRPC Integration with `elixir-grpc`**

Integrating `elixir-grpc` into Axon would be a significant step towards a high-performance, strongly-typed communication layer between Elixir and Python. Here's a breakdown:

**a) Protocol Buffers Definition (`.proto`)**

We'd start by defining our messages and services in a `.proto` file. This file serves as the contract between Elixir and Python.

```protobuf
// axon.proto
syntax = "proto3";

package axon;

service AgentService {
  rpc Run (RunRequest) returns (RunResponse) {}
  rpc RunStream (RunRequest) returns (stream RunResponseChunk) {}
}

message RunRequest {
  string agent_id = 1;
  string prompt = 2;
  repeated ModelMessage message_history = 3;
  map<string, string> model_settings = 4; // Simplified for now
}

message RunResponse {
  string result = 1; // Could be a oneof for text or structured data
  Usage usage = 2;
}

message RunResponseChunk {
  string data = 1; // For text streaming
  // Or, for structured data streaming, a repeated field of partial data updates
}

message ModelMessage {
  enum Kind {
    REQUEST = 0;
    RESPONSE = 1;
  }
  Kind kind = 1;
  repeated ModelMessagePart parts = 2;
  google.protobuf.Timestamp timestamp = 3; // Using google.protobuf.Timestamp
}

message ModelMessagePart {
  oneof part {
    SystemPromptPart system_prompt_part = 1;
    UserPromptPart user_prompt_part = 2;
    ToolReturnPart tool_return_part = 3;
    RetryPromptPart retry_prompt_part = 4;
    TextPart text_part = 5;
    ToolCallPart tool_call_part = 6;
  }
}

message SystemPromptPart {
  string content = 1;
}

message UserPromptPart {
  string content = 1;
  google.protobuf.Timestamp timestamp = 2;
}

message ToolReturnPart {
  string tool_name = 1;
  bytes content = 2; // Using bytes for Any
  string tool_call_id = 3;
}

message RetryPromptPart {
  string content = 1;
  string tool_name = 2;
  string tool_call_id = 3;
}

message TextPart {
  string content = 1;
}

message ToolCallPart {
  string tool_name = 1;
  bytes args = 2; // Using bytes for JSON-encoded arguments
  string tool_call_id = 3;
}

message Usage {
  int32 requests = 1;
  int32 request_tokens = 2;
  int32 response_tokens = 3;
  int32 total_tokens = 4;
  map<string, int32> details = 5;
}

message ToolDefinition {
  string name = 1;
  string description = 2;
  bytes parameters_json_schema = 3; // Using bytes for JSON schema
  string outer_typed_dict_key = 4;
}
```

**b) Code Generation**

We would run the `protoc` compiler using this in a `mix` task:
```bash
mix grpc.gen axon.proto
```

**c) Elixir gRPC Server (`axon_core/lib/axon_core/agent_grpc_server.ex`)**

```elixir
defmodule AxonCore.AgentGrpcServer do
  use GRPC.Server, service: Axon.AgentService.Service

  def run(request, stream) do
    # Get agent_id from the request
    agent_id = request.agent_id

    # Lookup the agent in the registry
    case AxonCore.AgentRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        # Forward the request to the agent process
        send(agent_pid, {:grpc_request, request, stream})

        # Return a response immediately, signaling that the request has been received
        Axon.RunResponse.new(result: "Request received", usage: Axon.Usage.new())

      {:error, :not_found} ->
        # Handle the case where the agent is not found
        # You can raise an error or return an appropriate response
        raise "Agent not found: #{agent_id}"
    end
  end

  def run_stream(request, stream) do
      # Get agent_id from the request
      agent_id = request.agent_id
      # Lookup the agent in the registry
      case AxonCore.AgentRegistry.lookup(agent_id) do
        {:ok, agent_pid} ->
          # Forward the request to the agent process
          send(agent_pid, {:grpc_stream_request, request, stream})
          # For a stream, we don't return anything here.
          # The agent process will handle sending chunks.
          {:ok, %{}}

        {:error, :not_found} ->
          # Handle the case where the agent is not found
          # You can raise an error or return an appropriate response
          raise "Agent not found: #{agent_id}"
      end
  end
end
```

**d) Elixir Agent Process (`axon_core/lib/axon_core/agent_process.ex`)**

```elixir
defmodule AxonCore.AgentProcess do
  use GenServer

  # ... (start_link, init, etc.)

  # Handle gRPC requests
  def handle_info({:grpc_request, request, stream}, state) do
    # 1. Extract data from the request (prompt, message history, etc.)
    # 2. Construct the message to be sent to the Python agent
    # 3. Send the message to the Python agent (we'll need a way to identify the Python process)
    # 4. Handle the response from the Python agent
    # 5. Send a response back to the client via the stream
    {:noreply, state}
  end

  # Handle gRPC streaming requests
  def handle_info({:grpc_stream_request, request, stream}, state) do
    # ... Similar to handle_info/3, but we need to send chunks to the client via stream.send/2
    {:noreply, state}
  end

  # ... (other handlers for managing the Python process)
end
```

**e) Python gRPC Client (`axon_python/src/axon_python/agent_wrapper.py`)**

```python
import grpc
from axon_python.generated import axon_pb2, axon_pb2_grpc  # Assuming you named your proto file "axon.proto"
from pydantic_ai.agent import Agent  # Or your agent class

class AgentServicer(axon_pb2_grpc.AgentServiceServicer):
    def __init__(self, agent: Agent):
        self.agent = agent

    def Run(self, request, context):
        # Convert the gRPC request to the format expected by your agent
        prompt = request.prompt
        message_history = [self._convert_message(msg) for msg in request.message_history]

        # Run the agent
        result = self.agent.run_sync(prompt, message_history=message_history)

        # Convert the result to a gRPC response
        return axon_pb2.RunResponse(
            result=result.data,
            usage=axon_pb2.Usage(
                requests=result.usage.requests,
                request_tokens=result.usage.request_tokens,
                response_tokens=result.usage.response_tokens,
                total_tokens=result.usage.total_tokens,
            )
        )

    def RunStream(self, request, context):
        # Convert the gRPC request to the format expected by your agent
        prompt = request.prompt
        message_history = [self._convert_message(msg) for msg in request.message_history]

        # Run the agent in streaming mode
        for chunk in self.agent.run_stream(prompt, message_history=message_history):
            # Convert each chunk to a gRPC response
            yield axon_pb2.RunResponseChunk(data=chunk)

    def _convert_message(self, msg):
        # Convert a gRPC ModelMessage to a pydantic-ai ModelMessage
        # ... (implementation depends on your message format)
        pass

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    axon_pb2_grpc.add_AgentServiceServicer_to_server(AgentServicer(agent), server)
    server.add_insecure_port('[::]:50051')  # Specify the port your agent should listen on
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
```

**f) Update `start_agent.sh`:**

```bash
#!/bin/bash
# ... (activate venv)

AGENT_MODULE="$1"
PORT="$2" #now grpc port
MODEL="$3"

# Set environment variables for the agent
export AXON_PYTHON_AGENT_PORT="$PORT"
export AXON_PYTHON_AGENT_MODEL="$MODEL"

# Start the gRPC server
python -m axon_python.agent_wrapper # Assuming your server code is in agent_wrapper.py
```

**Why This is More Complex:**

1. **Schema Definition:**  Protocol Buffers require a strict schema, adding a layer of formality.
2. **Code Generation:**  You need to generate code for both Elixir and Python, which adds steps to your development workflow.
3. **Binary Format:**  Debugging requires understanding the binary format of Protobuf messages.
4. **Less Mature Ecosystem (in Elixir):** While `elixir-grpc` seems well-maintained, the gRPC ecosystem in Elixir is not as extensive as the HTTP ecosystem.

**When to Use gRPC:**

*   **Performance is critical:** When the overhead of HTTP becomes a bottleneck.
*   **Real-time streaming:** When you need efficient bidirectional streaming.
*   **Complex data structures:** When you're dealing with deeply nested or complex data that benefits from a strict schema.

**Recommendation:**

Start with HTTP for simplicity. If performance becomes an issue, carefully evaluate whether the benefits of gRPC outweigh the added complexity in your specific use case.

**3. `pydantic-ai` Examples and Axon's Value Proposition**

Let's use the `chat_app.py` example to demonstrate how Axon adds value and how we can leverage Elixir's strengths.

**`pydantic-ai` Example: `chat_app.py`**

This example implements a simple chat application using FastAPI and demonstrates:

*   Reusing chat history.
*   Serializing messages.
*   Streaming responses.

```python
#! examples/pydantic_ai_examples/chat_app.py
import json
from typing import Union, AsyncIterator
from datetime import datetime

import uvicorn
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel, Field

from pydantic_ai import Agent

class ChatMessage(BaseModel):
    """Chat message model."""

    role: str = Field(description='Role of the message sender, e.g. "user" or "assistant"')
    content: str = Field(description='Content of the message')
    timestamp: datetime = Field(default_factory=datetime.now, description='Timestamp of the message')

class ChatHistory(BaseModel):
    """Chat history model."""

    messages: list[ChatMessage] = Field(
        default_factory=list, description='List of chat messages, stored in order of occurrence'
    )

# agent which constrained to only return text
chat_agent = Agent('gemini-1.5-flash', system_prompt='You are a helpful assistant.')

app = FastAPI(title='pydantic-ai chat app example')
# dictionary to store chat histories, in a real application this would be a database
chat_histories: dict[int, ChatHistory] = {}
# for demo simplicity we use a simple incrementing integer, in a real application this would be a UUID
next_chat_id = 1

@app.get('/', response_class=HTMLResponse)
async def index():
    """Serve the index page."""
    return """
<!DOCTYPE html>
<html>
<head>
    <title>Chat</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <div class="container mx-auto p-4">
        <h1 class="text-2xl mb-4">Chat</h1>
        <div id="chat-history" class="mb-4 overflow-y-auto h-64 border border-gray-300 p-4 bg-white rounded">
            <!-- Chat messages will be appended here -->
        </div>
        <div class="mb-4">
            <label for="chat-id" class="block mb-2">Chat ID:</label>
            <select id="chat-id" class="w-full border border-gray-300