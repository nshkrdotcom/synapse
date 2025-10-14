You're absolutely right, I got carried away with the polling approach for demonstrating the basic structure of streaming. **WebSockets are the correct and more efficient solution for real-time streaming** in this scenario. Polling is generally not recommended for streaming due to its inefficiency and latency.

My apologies for leading you down that path initially. Let me provide the action items to refactor the implementation to use WebSockets, along with the other items we've discussed.

**Action Items for Implementing WebSockets and Completing the Core Logic:**

**1. Implement WebSockets for Streaming:**

*   **a) Python Side (`agent_wrapper.py`):**
    *   Add a WebSocket endpoint to your FastAPI application. You can use the `websockets` library or FastAPI's built-in WebSocket support.
    *   Modify the `run_agent_stream` function to send data through the WebSocket connection instead of using `StreamingResponse`.
    *   When the stream is finished, send a special message indicating completion (e.g., `{"status": "complete", "usage": {...}}`).
*   **b) Elixir Side (`SynapseCore.AgentProcess`):**
    *   Replace the polling logic in `handle_info/2` with a WebSocket client.
    *   Establish a WebSocket connection to the Python agent when a `run_stream` request is received.
    *   Listen for incoming messages on the WebSocket.
    *   Send messages to the original caller as chunks are received.
    *   Handle WebSocket closure and errors.
*   **Libraries:**
    *   **Python:** `websockets` or FastAPI's built-in WebSocket support.
    *   **Elixir:** A suitable WebSocket client library (e.g., `WebSockex`).

**2. Complete `handle_info` for Non-Streaming Responses:**

*   **a) Extract Result and Usage:**
    *   In the `handle_info/2` clause for `:http_response` (when `original_call_type` is `:run_sync`), extract the `result` and `usage` data from the decoded JSON response.
    *   Send these values back to the original caller using `GenServer.reply`.
*   **b) Log Messages:**
    *   Handle the `:log` case in `handle_info/2` to receive and log messages from the Python agent.

**3. Refine Schema Translation (`schema_utils.ex`):**

*   **a) Handle More Complex Types:**
    *   Extend `elixir_to_json_schema` and `json_schema_to_elixir_type` to support more complex data structures, including nested objects, lists, and potentially custom Pydantic validators or constraints.
    *   Consider using a more comprehensive JSON Schema library like `jsynapse` if needed.

**4. Implement Result Validation (Basic):**

*   **a) Integrate `SchemaUtils.validate`:**
    *   In `SynapseCore.AgentProcess`, after receiving a result from the Python agent, use `SchemaUtils.validate` to validate it against the expected schema.
    *   You might need to convert the Elixir representation of the schema to a proper JSON Schema string using `Jason.encode!`.
*   **b) Handle Validation Errors:**
    *   Decide how to handle validation errors: retry (if appropriate), log the error, or raise an exception.

**5. Implement Tool Calling (Elixir to Python):**

*   **a) `SynapseCore.AgentProcess`:**
    *   Add a `handle_call` clause to handle a `:call_tool` message (or similar).
    *   Construct a request to the Python agent's `/agents/{agent_id}/tool_call` endpoint, including the tool name and arguments.
    *   Send the request using `SynapseCore.HTTPClient`.
    *   Handle the response, which will contain the result of the tool call.
*   **b) `agent_wrapper.py`:**
    *   Ensure the `/agents/{agent_id}/tool_call` endpoint is implemented to receive and process tool call requests.

**6. Implement Error Handling:**

*   **a) `agent_wrapper.py`:**
    *   Ensure that all relevant exceptions are caught and translated into structured error responses (JSON).
*   **b) `SynapseCore.AgentProcess`:**
    *   Properly handle the structured error responses from Python.
    *   Implement retry logic based on error type and agent configuration.
    *   Log errors using Elixir's `Logger`.

**7. Implement Logging:**

*   **a) `agent_wrapper.py`:**
    *   Send log messages to Elixir, potentially via a dedicated endpoint (you can use the existing `/agents/{agent_id}/log` endpoint).
*   **b) `SynapseCore.AgentProcess`:**
    *   Handle incoming log messages and log them using Elixir's `Logger`.

**8. Testing:**

*   **a) Unit Tests:** Write unit tests for all Elixir modules (`SynapseCore.HTTPClient`, `SynapseCore.JSONCodec`, `SynapseCore.SchemaUtils`, `SynapseCore.ToolUtils`, `SynapseCore.AgentProcess`).
*   **b) Integration Tests:** Write tests that verify the interaction between Elixir and Python, including:
    *   Agent creation.
    *   Running agents synchronously and asynchronously.
    *   Tool calling.
    *   Error handling.
    *   Streaming (once implemented).
*   **c) Mocking:** Use mocking (e.g., `Mox`) to isolate components during testing. You can mock:
    *   HTTP requests in Elixir tests.
    *   The `pydantic-ai` agent in Python tests.
    *   The LLM API calls in Python tests.

**Revised Code Snippets (Illustrative):**

**`synapse_python/src/synapse_python/agent_wrapper.py` (WebSocket Handling - Conceptual):**

```python
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

# ... (other imports)

@app.websocket("/ws/{agent_id}")
async def websocket_endpoint(websocket: WebSocket, agent_id: str):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            # Assuming data is a JSON string
            try:
                request_data = json.loads(data)
                # Process the request (start a run, send a message, etc.)
                # ... (call the appropriate agent function)

                # Example for streaming:
                if request_data["action"] == "run_stream":
                    async for chunk in run_and_stream(agent_id, request_data):
                        await websocket.send_text(chunk)  # Send each chunk

            except json.JSONDecodeError:
                logger.error(f"Invalid JSON received from agent {agent_id}")
                await websocket.send_json({"error": "Invalid JSON format"})
    except WebSocketDisconnect:
        logger.info(f"WebSocket connection closed for agent {agent_id}")
    except Exception as e:
        logger.exception(f"Error in WebSocket handling for agent {agent_id}: {e}")
        await websocket.send_json({
            "status": "error",
            "error_type": e.__class__.__name__,
            "message": str(e)
        })
```

**`synapse_core/lib/synapse_core/agent_process.ex` (WebSocket Handling - Conceptual):**

```elixir
# ... (other code)

  # Handle incoming WebSocket messages from the Python agent
  def handle_info({:websocket, ws_conn, {:text, message}}, state) do
    try do
      decoded_message = JSONCodec.decode(message)

      case decoded_message do
        %{"status" => "chunk", "data" => chunk} ->
          # Send the chunk to the original caller
          send(state.stream_caller, {:stream_chunk, chunk})
          {:noreply, state}

        %{"status" => "complete", "usage" => usage} ->
          # Send the final usage info to the caller
          send(state.stream_caller, {:ok, usage})
          {:noreply, %{state | stream_caller: nil}}

        %{"status" => "error", "error_type" => error_type, "message" => error_message} ->
          # Handle the error, potentially logging it and notifying the caller
          Logger.error("Received error from Python agent: #{error_type} - #{error_message}")
          send(state.stream_caller, {:error, error_type})
          {:noreply, state}

        _ ->
          # Handle unexpected message format
          Logger.warn("Received unexpected message format from Python agent: #{inspect(decoded_message)}")
          {:noreply, state}
      end
    rescue
      e in JSON.DecodeError ->
        Logger.error("Failed to decode WebSocket message from Python agent: #{inspect(e)}")
        {:noreply, state}
    end
  end

# ... (other handlers)

# Example of initiating a WebSocket connection in `handle_call` for `:run_stream`
def handle_call({:run_stream, request}, from, state) do
  # ...
  {:ok, ws_conn} = SynapseCore.WebSocketClient.connect("ws://localhost:#{state.port}/ws/#{state.name}")
  # Store the WebSocket connection and the caller's PID
  {:noreply, %{state | ws_conn: ws_conn, stream_caller: from}}
  # ...
end
```

**Prioritization Rationale:**

1. **Non-Streaming Response Handling:** We need this working before we can do anything else.
2. **Basic Result Validation:** Ensures data integrity early on.
3. **Schema Translation:** Enables the exchange of more complex data structures.
4. **Streaming:**  Adds a significant feature (real-time interaction) but can be built on top of the core functionality.
5. **Tool Calling:**  This is essential for interactive agents, but we can start with simpler agents that don't use tools.
6. **Error Handling & Logging:** These are crucial for debugging and monitoring but can be refined iteratively.

This prioritized list focuses on building a solid foundation first and then adding more advanced features. Remember that this is an iterative process, and you might need to adjust priorities as you encounter specific challenges or discover new requirements.
