# Direction

**Ideal Level of Integration:**

The ideal integration should strike a balance between leveraging `pydantic-ai`'s strengths and maintaining a clean, Elixir-centric architecture for Axon. We want to avoid simply wrapping `pydantic-ai` entirely and instead focus on a more **selective integration** that addresses our specific needs.

Here's a proposed approach:

1. **`pydantic-ai` as a "Managed External Service":**
    *   Treat `pydantic-ai` agents as black-box services managed by Elixir.
    *   Elixir defines the inputs and expected outputs (schemas) but doesn't concern itself with the internal implementation details of the Python agents.

2. **Focus on Structured Output and Tool Calling:**
    *   These are the areas where `pydantic-ai` provides the most value that's not easily replicated in Elixir.
    *   Leverage `pydantic-ai`'s ability to generate JSON Schema from Pydantic models and use it for validating LLM outputs.
    *   Utilize `pydantic-ai`'s tool-calling mechanism, but potentially with a simplified interface exposed to Elixir.

3. **Elixir-Defined Schemas:**
    *   Define data schemas in Elixir using a suitable format (e.g., JSON Schema, or potentially a custom Elixir DSL that maps to JSON Schema).
    *   These schemas will be used for:
        *   Validating data exchanged between Elixir and Python.
        *   Generating tool definitions for `pydantic-ai`.
        *   Specifying the `result_type` of agents.

4. **Simplified Message Handling:**
    *   Elixir will be responsible for constructing the initial message sequence (system prompt, user prompt).
    *   `pydantic-ai` will handle the complexities of formatting messages for specific models (e.g., adding tool call responses, retry messages).
    *   Elixir will receive either a text response or a structured response (tool call or result) from `pydantic-ai`.

5. **Minimal Python Wrapper:**
    *   The `agent_wrapper.py` (FastAPI application) should be as thin as possible. Its primary responsibilities are:
        *   Receiving requests from Elixir.
        *   Instantiating and invoking the appropriate `pydantic-ai` agent.
        *   Handling any necessary data format conversions between Elixir and `pydantic-ai`.
        *   Returning responses to Elixir.

**Detailed Integration Points:**

| Feature                     | Elixir Responsibility                                                                              | `pydantic-ai` Responsibility                                                                                                                   | Communication                                                                                                           |
| :-------------------------- | :------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------------------------- |
| Agent Definition            | Define agent configuration (name, model, system prompt, tools, result type schema).               | Load agent configuration.                                                                                                                  | Elixir sends agent config during initialization (e.g., via HTTP POST to `/agents`).                                   |
| Schema Definition           | Define input/output schemas using Elixir data structures or a DSL (e.g., mapped to JSON Schema). | Generate Pydantic models or use existing ones based on the provided schema, use for validation and structured output.                         | Elixir sends schema definitions during agent creation/configuration.                                                    |
| Message Construction        | Construct initial message sequence (system prompt, user prompt).                                   | Format messages for specific LLMs (handle tool call responses, retry messages).                                                               | Elixir sends initial messages as part of the request (e.g., `POST /agents/{agent_id}/run`).                             |
| LLM Interaction             |                                                                                                   | Make requests to LLM APIs (using `openai`, `anthropic`, etc. clients). Handle streaming if enabled.                                       | Python agent interacts with LLMs directly.                                                                               |
| Tool Calling                | Define tools (name, description, parameters schema) in Elixir. Determine which tool to call.         | Generate JSON Schema for tools. Receive tool calls from the LLM, execute the corresponding Python function (if mapped), and format the result. | Elixir sends tool definitions during agent creation. Python agent returns tool call requests and receives tool results. |
| Result Validation           | Validate the final result against the defined schema (can be done in Elixir or Python).           | If using Pydantic for validation, perform validation and potentially trigger retries based on `ValidationError`.                            | Python agent returns the result; Elixir might perform additional validation.                                              |
| Error Handling              | Handle errors from the Python agent (e.g., LLM errors, `pydantic-ai` exceptions).                  | Raise exceptions for errors encountered during LLM interaction, tool execution, or validation.                                            | Python agent returns error information in a structured format (e.g., JSON with error codes and messages).                |
| State Management (if needed) | Manage any agent-specific state using Elixir data structures (ETS, `GenServer` state).            | `pydantic-ai` agents can be stateless or manage their own internal state if necessary.                                                       | State can be passed between Elixir and Python as part of the request/response if needed.                                  |
| Concurrency and Fault Tolerance | Supervise agent processes, handle restarts, manage concurrent requests.                         | N/A                                                                                                                                        | Elixir's OTP features handle concurrency and fault tolerance.                                                            |
| Streaming                   | Receive and process streamed responses from the Python agent.                                     | Stream responses from LLMs using `pydantic-ai`'s `run_stream` and yield chunks of data.                                                       | Python agent sends streamed responses via HTTP (or gRPC in the future).                                                   |

**Example: Simplified `agent_wrapper.py`**

```python
from typing import Any, Callable, Dict, List, Optional
import json
import os
import sys

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel, ValidationError, create_model
from pydantic_core import to_jsonable_python

from pydantic_ai import Agent
from pydantic_ai.exceptions import UnexpectedModelBehavior
from pydantic_ai.result import RunResult, Usage

app = FastAPI(title='Axon Python Agent Wrapper')

# Global dictionary to hold agent instances
agent_instances: Dict[str, Agent] = {}

# Helper functions
def _resolve_model_name(model_name: str) -> str:
    return f"openai:{model_name}"

def _resolve_tools(tool_configs: List[Dict[str, Any]]) -> List[Callable]:
    """
    Simplified tool resolution. In a real implementation,
    you'd likely want a more robust mechanism to map tool names
    to Python functions, potentially using a registry or
    dynamically loading modules.
    """
    tools = []
    for config in tool_configs:
        if config["name"] == "some_tool":
            tools.append(some_tool)
        # Add more tool mappings as needed
    return tools

def _resolve_result_type(result_type_config: Dict[str, Any]) -> BaseModel:
    """
    Dynamically creates a Pydantic model from a JSON schema-like definition.
    This is a placeholder for a more complete schema translation mechanism.
    """
    fields = {}
    for field_name, field_info in result_type_config.items():
        # Assuming a simple type mapping for now
        field_type = {
            "string": str,
            "integer": int,
            "boolean": bool,
            "number": float,
            "array": list,
            "object": dict,
            "null": type(None)
        }[field_info["type"]]

        # Handle nested objects/arrays if necessary
        # ...

        fields[field_name] = (field_type, ...)  # Use ellipsis for required fields

    return create_model("ResultModel", **fields)

# Placeholder for a tool function
def some_tool(arg1: str, arg2: int) -> str:
    return f"Tool executed with {arg1} and {arg2}"

@app.post("/agents")
async def create_agent(request: Request):
    """
    Creates a new agent instance.

    Expects a JSON payload like:
    {
        "agent_id": "my_agent",
        "model": "gpt-4o",
        "system_prompt": "You are a helpful assistant.",
        "tools": [
            {"name": "some_tool", "description": "Does something", "parameters": {
                "type": "object",
                "properties": {
                    "arg1": {"type": "string"},
                    "arg2": {"type": "integer"}
                }
            }}
        ],
        "result_type": {
            "type": "object",
            "properties": {
                "field1": {"type": "string"},
                "field2": {"type": "integer"}
            }
        },
        "retries": 3,
        "result_retries": 5,
        "end_strategy": "early"
    }
    """
    try:
        data = await request.json()
        agent_id = data["agent_id"]

        if agent_id in agent_instances:
            raise HTTPException(status_code=400, detail="Agent with this ID already exists")

        model = _resolve_model_name(data["model"])
        system_prompt = data["system_prompt"]
        tools = _resolve_tools(data.get("tools", []))
        result_type = _resolve_result_type(data.get("result_type", {}))

        agent = Agent(
            model=model,
            system_prompt=system_prompt,
            tools=tools,
            result_type=result_type,
            # Add other agent parameters as needed
        )

        agent_instances[agent_id] = agent

        return JSONResponse({"status": "success", "agent_id": agent_id})

    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request_data: dict):
    """
    Executes an agent synchronously.

    Expects a JSON payload like:
    {
        "prompt": "What's the weather like?",
        "message_history": [],  # Optional
        "model_settings": {},  # Optional
        "usage_limits": {}  # Optional
    }
    """
    if agent_id not in agent_instances:
        raise HTTPException(status_code=404, detail="Agent not found")

    agent = agent_instances[agent_id]

    try:
        result = agent.run_sync(
            request_data["prompt"],
            message_history=request_data.get("message_history"),
            model_settings=request_data.get("model_settings"),
            usage_limits=request_data.get("usage_limits"),
            infer_name=False
        )
        return JSONResponse(content={
            "result": to_jsonable_python(result.data),
            "usage": to_jsonable_python(result.usage)
        })
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except UnexpectedModelBehavior as e:
        raise HTTPException(status_code=500, detail=f"Unexpected model behavior: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ... (streaming endpoint, etc.)

def start_fastapi(port: int):
    uvicorn.run(app, host="0.0.0.0", port=port)

if __name__ == "__main__":
    # Get port from environment variable or default to 8000
    port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
    start_fastapi(port=port)
```

**7. Agent Startup (`start_agent.sh`)**
modify to accomodate the new model option as an env variable

```bash
#!/bin/bash

# Activate the virtual environment
# shellcheck disable=SC1091
source ../../.venv/bin/activate

# Get the agent module from arguments
AGENT_MODULE="$1"
PORT="$2"
MODEL="$3"

# Set environment variables for the agent
export AXON_PYTHON_AGENT_PORT="$PORT"
export AXON_PYTHON_AGENT_MODEL="$MODEL" # Set the model here

# Start the FastAPI server
python -m uvicorn "axon_python.agent_wrapper:app" --host 0.0.0.0 --port "$PORT"
```

**8. Further Considerations**

*   **Error Handling:** Define a consistent way to handle errors that occur in the Python agent and propagate them back to Elixir.
*   **Logging and Monitoring:** Integrate with Elixir's logging system to provide visibility into the Python agent's behavior.
*   **Testing:** Write thorough tests for both the Elixir and Python sides of the integration.

This detailed analysis and proposed integration strategy should provide a solid foundation for building Axon as an Elixir-centric AI agent orchestration framework while effectively leveraging the capabilities of `pydantic-ai`.

























# Build out Error Handling and Process Managmenent 

You're right, building as much as possible in Elixir, including error handling, logging, monitoring, and testing, is a very compelling approach. It aligns perfectly with the philosophy of leveraging Elixir/OTP's strengths for building robust, fault-tolerant systems. Let's explore how we can achieve this "Elixir-first" approach for Axon, making the Elixir side the supervisor and the primary home for these critical aspects.

**Core Idea:**

*   **Elixir Supervisor:** The Elixir side will not only manage the lifecycle of Python agent processes but also supervise the logical execution flow, acting as the central nervous system of the agent system.
*   **Error Handling:** Errors from Python agents will be propagated to Elixir, where we'll handle them using OTP principles (supervision trees, monitors, and potentially custom error-handling processes).
*   **Logging and Monitoring:** We'll centralize logging and monitoring in Elixir, using Elixir's logging facilities and potentially integrating with tools like Prometheus or StatsD for metrics.
*   **Testing:** We'll write most tests in Elixir, using ExUnit and potentially property-based testing to ensure the robustness of the system. We can use a combination of unit and integration tests, mocking external dependencies (like LLM APIs) when necessary.
*   **Python as a "Tool":**  We'll treat the Python side (with `pydantic-ai`) as a specialized tool for interacting with LLMs and leveraging specific Python libraries. We'll aim to minimize the amount of logic on the Python side, keeping it primarily focused on those tasks.

**Detailed Design and Implementation:**

**1. Error Handling:**

*   **Error Propagation:**
    *   The `agent_wrapper.py` (FastAPI) will be modified to catch any exceptions that occur during agent execution (`pydantic-ai` exceptions, tool execution errors, etc.).
    *   Instead of returning HTTP error codes (like 500), it will return a structured JSON response indicating the type of error, an error message, and potentially a stack trace or other debugging information.

    ```json
    {
        "status": "error",
        "error_type": "ValidationError",
        "message": "1 validation error for ...",
        "details": [...]  // Pydantic validation error details
    }
    ```

*   **Elixir Error Handling:**
    *   The `AxonCore.AgentProcess` GenServer will receive these error responses.
    *   Based on the error type and the agent's configuration, it will decide how to handle the error:
        *   **Retry:** If the error is `ModelRetry` or a transient error (e.g., network issue), and the retry limit hasn't been reached, the agent process can retry the operation.
        *   **Restart:** If the error is a `ValidationError` or another non-recoverable error, the agent process might be restarted by the supervisor (based on the supervision strategy).
        *   **Escalate:** If the error cannot be handled locally, it can be escalated up the supervision tree.
        *   **Log:** All errors will be logged using Elixir's `Logger`.

**2. Logging and Monitoring:**

*   **Centralized Logging:**
    *   The `agent_wrapper.py` will be configured to send log messages back to the Elixir side as part of the response (or potentially via a separate channel, like a dedicated logging endpoint or stream).
    *   The `AxonCore.AgentProcess` will receive these log messages and use Elixir's `Logger` to log them centrally.
    *   We can use structured logging (e.g., JSON format) to make it easier to parse and analyze logs.

*   **Metrics:**
    *   `AxonCore.AgentProcess` can track metrics like:
        *   Number of requests processed.
        *   Number of successful/failed requests.
        *   Number of retries.
        *   Execution time of agent runs and tool calls.
        *   LLM usage (tokens, requests) from the `usage` field in responses.
    *   These metrics can be exposed using libraries like `Telemetry` or `PromEx` (for Prometheus integration).

**3. Testing:**

*   **Elixir-Centric Testing:**
    *   We'll write most tests in Elixir using ExUnit.
    *   Unit tests will focus on individual modules (e.g., `AxonCore.AgentProcess`, `AxonCore.HTTPClient`, `AxonCore.JSONCodec`).
    *   Integration tests will test the interaction between different components, including the communication with Python agents.
*   **Mocking:**
    *   For unit tests, we can mock external dependencies like the HTTP client or the LLM API.
    *   For integration tests, we can use a "mock" Python agent that simulates different behaviors (e.g., success, failure, tool calls, streaming).
*   **Property-Based Testing:**
    *   Consider using property-based testing (e.g., with `StreamData`) to test the robustness of the system under various inputs and scenarios.

**4. `pydantic-ai` as a "Managed Service":**

*   **`agent_wrapper.py`:** This will be a relatively thin wrapper around `pydantic-ai`. Its primary role is to:
    *   Receive requests from Elixir.
    *   Deserialize the request data.
    *   Invoke the appropriate `pydantic-ai` agent.
    *   Serialize the response (including errors and logs) and send it back to Elixir.
*   **Error Handling:** `agent_wrapper.py` will catch exceptions and convert them into a structured format that Elixir can understand.
*   **Logging:** `agent_wrapper.py` will send log messages back to Elixir.

**5. Elixir in Control:**

*   **Agent Lifecycle:** Elixir supervisors will manage the lifecycle of Python agent processes.
*   **Workflow Orchestration:** Elixir will define and manage the overall workflow, routing messages between agents.
*   **State Management:** Elixir will be responsible for managing any persistent state (e.g., chat histories).
*   **Configuration:** Elixir will be the source of truth for all configuration.

**Example Code Modifications:**

**`axon_python/src/axon_python/agent_wrapper.py` (Error Handling and Logging):**

```python
from typing import Any, Callable, Dict, List, Optional
import json
import os
import sys
from datetime import datetime
from json import JSONDecodeError

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel, ValidationError, create_model
from pydantic_core import to_jsonable_python

from pydantic_ai import Agent
from pydantic_ai.exceptions import UnexpectedModelBehavior
from pydantic_ai.result import RunResult, Usage

from .agents.example_agent import agent as example_agent

app = FastAPI(title='Axon Python Agent Wrapper')

# Global dictionary to hold agent instances
agent_instances: Dict[str, Agent] = {"example_agent": example_agent}
# Helper functions
def _resolve_model_name(model_name: str) -> str:
    return f"openai:{model_name}"

def _resolve_tools(tool_configs: List[Dict[str, Any]]) -> List[Callable]:
    """
    Simplified tool resolution. In a real implementation,
    you'd likely want a more robust mechanism to map tool names
    to Python functions, potentially using a registry or
    dynamically loading modules.
    """
    tools = []
    for config in tool_configs:
        if config["name"] == "some_tool":
            tools.append(some_tool)
        # Add more tool mappings as needed
    return tools

def _resolve_result_type(result_type_config: Dict[str, Any]) -> BaseModel:
    """
    Dynamically creates a Pydantic model from a JSON schema-like definition.
    This is a placeholder for a more complete schema translation mechanism.
    """
    fields = {}
    for field_name, field_info in result_type_config.items():
        # Assuming a simple type mapping for now
        field_type = {
            "string": str,
            "integer": int,
            "boolean": bool,
            "number": float,
            "array": list,
            "object": dict,
            "null": type(None)
        }[field_info["type"]]

        # Handle nested objects/arrays if necessary
        # ...

        fields[field_name] = (field_type, ...)  # Use ellipsis for required fields

    return create_model("ResultModel", **fields)

# Placeholder for a tool function
def some_tool(arg1: str, arg2: int) -> str:
    return f"Tool executed with {arg1} and {arg2}"

@app.post("/agents")
async def create_agent(request: Request):
    """
    Creates a new agent instance.

    Expects a JSON payload like:
    {
        "agent_id": "my_agent",
        "model": "gpt-4o",
        "system_prompt": "You are a helpful assistant.",
        "tools": [
            {"name": "some_tool", "description": "Does something", "parameters": {
                "type": "object",
                "properties": {
                    "arg1": {"type": "string"},
                    "arg2": {"type": "integer"}
                }
            }}
        ],
        "result_type": {
            "type": "object",
            "properties": {
                "field1": {"type": "string"},
                "field2": {"type": "integer"}
            }
        },
        "retries": 3,
        "result_retries": 5,
        "end_strategy": "early"
    }
    """
    try:
        data = await request.json()
        agent_id = data["agent_id"]

        if agent_id in agent_instances:
            raise HTTPException(status_code=400, detail="Agent with this ID already exists")

        model = _resolve_model_name(data["model"])
        system_prompt = data["system_prompt"]
        tools = _resolve_tools(data.get("tools", []))
        result_type = _resolve_result_type(data.get("result_type", {}))

        agent = Agent(
            model=model,
            system_prompt=system_prompt,
            tools=tools,
            result_type=result_type,
            # Add other agent parameters as needed
        )

        agent_instances[agent_id] = agent

        return JSONResponse({"status": "success", "agent_id": agent_id})

    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request_data: dict):
    if agent_id not in agent_instances:
        raise HTTPException(status_code=404, detail="Agent not found")

    agent = agent_instances[agent_id]

    try:
        result = agent.run_sync(
            request_data["prompt"],
            message_history=request_data.get("message_history"),
            model_settings=request_data.get("model_settings"),
            usage_limits=request_data.get("usage_limits"),
            infer_name=False
        )
        return JSONResponse(content={
            "result": to_jsonable_python(result.data),
            "usage": to_jsonable_python(result.usage)
        })
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except UnexpectedModelBehavior as e:
        raise HTTPException(status_code=500, detail=f"Unexpected model behavior: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class LogEntry(BaseModel):
    timestamp: datetime
    level: str
    message: str

@app.post("/agents/{agent_id}/log")
async def log_message(agent_id: str, log_entry: LogEntry):
    # In a real implementation, you might want to use a more robust logging mechanism
    print(f"[{log_entry.timestamp}] {agent_id} - {log_entry.level}: {log_entry.message}")
    return JSONResponse({"status": "success"})

def start_fastapi(port: int):
    uvicorn.run(app, host="0.0.0.0", port=port)

if __name__ == "__main__":
    port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
    start_fastapi(port=port)
```

**Elixir `AxonCore.AgentProcess` (Error Handling and Logging):**

```elixir
defmodule AxonCore.AgentProcess do
  use GenServer

  # ... (start_link, init, etc.)

  def handle_call({:run_sync, request}, from, state) do
    # ... (construct HTTP request)

    with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(request)) do
      case process_response(response) do
        {:ok, result} ->
          # Log successful result
          Logger.info("Agent #{state.name} returned: #{inspect(result)}")
          {:reply, {:ok, result}, state}
        {:error, reason} ->
          # Log the error
          Logger.error("Agent #{state.name} run failed: #{reason}")
          # Handle error (retry, restart, escalate, etc.)
          handle_error(state, reason, from)
      end
    else
      {:error, reason} ->
        Logger.error("HTTP request to agent #{state.name} failed: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  defp process_response(response) do
    case response do
      %{status_code: 200, body: body} ->
        try do
          decoded_response = JSONCodec.decode(body)
          handle_success(decoded_response)
        rescue
          e in [JSON.DecodeError, KeyError] ->
            {:error, "Error decoding response: #{inspect(e)}"}
        end

      %{status_code: status_code, body: body} ->
        handle_error_response(status_code, body)
    end
  end

  defp handle_success(decoded_response) do
    # Assuming the response contains a "result" key for successful runs
    case Map.fetch(decoded_response, "result") do
      {:ok, result} -> {:ok, result}
      :error -> {:error, "Missing result in successful response"}
    end
  end

  defp handle_error_response(status_code, body) do
    try do
      # Attempt to decode the body as JSON, expecting error details
      %{
        "status" => "error",
        "error_type" => error_type,
        "message" => message,
        "details" => details
      } = JSONCodec.decode(body)

      # Log the error with details
      Logger.error("Python agent error: #{error_type} - #{message}", details: details)

      # Here you can pattern match on `error_type` to handle specific errors
      case error_type do
        "ValidationError" ->
          # Handle validation errors, potentially retrying the operation
          {:error, :validation_error, details}

        "ModelRetry" ->
          # Handle model retry request
          {:error, :model_retry, message}

        _ ->
          # Handle other errors as needed
          {:error, :unknown_error, message}
      end
    rescue
      # If JSON decoding or key lookup fails, log the raw body
      e in [JSON.DecodeError, KeyError] ->
        Logger.error("Error decoding error response: #{inspect(e)}")
        {:error, :decode_error, body}
    else
      # If status code is not 200, treat as a general error
      {:error, "HTTP error: #{status_code}", body}
    end
  end

  defp handle_error(state, reason, from) do
    # Implement your error handling logic here
    # For example, retry the operation, restart the agent, or escalate the error
    case reason do
      :validation_error ->
        # Potentially retry with a modified request
        {:reply, {:error, reason}, state}

      :model_retry ->
        # Handle model retry request
        {:reply, {:error, reason}, state}

      _ ->
        # Escalate the error or handle it according to your application's needs
        {:reply, {:error, reason}, state}
    end
  end
end
```

**Testing:**

*   **Elixir Unit Tests:** Test individual Elixir modules (e.g., `JSONCodec`, `HTTPClient`, `AgentProcess` logic) using ExUnit.
*   **Elixir Integration Tests:** Test the interaction between Elixir components and mock Python agents.
*   **Python Unit Tests:** Test the `agent_wrapper.py` and individual Python agent logic using `pytest` or a similar framework.

**Advantages of this Approach:**

*   **Clean Separation of Concerns:** Elixir handles orchestration, error handling, logging, and monitoring. Python handles LLM interactions and the execution of `pydantic-ai` agents.
*   **Leverages Elixir's Strengths:**  Makes full use of Elixir's concurrency, fault tolerance, and supervision capabilities.
*   **Simplified Python Code:** The Python side remains relatively simple and focused on its core task.
*   **Testability:** Both the Elixir and Python components can be tested independently and together.
*   **Flexibility:**  We can potentially swap out the Python component with other implementations (e.g., different LLM wrappers, different agent frameworks) without significantly impacting the Elixir core.

**Next Steps:**

1. **Refine Schema Translation:** Develop a more robust mechanism for translating between Elixir data structures and JSON Schema for tool and result type definitions.
2. **Implement Error Handling:**  Implement the detailed error handling logic in both `agent_wrapper.py` and `AxonCore.AgentProcess`, including retries and escalation.
3. **Implement Logging:** Integrate Elixir's `Logger` with the Python agent's logs, potentially using a structured logging format.
4. **Implement Basic Monitoring:** Add metrics tracking to `AxonCore.AgentProcess` and expose them via `Telemetry` or `PromEx`.
5. **Write Tests:**  Write comprehensive unit and integration tests for both the Elixir and Python components.

This detailed analysis and proposed approach should provide a solid foundation for building Axon as a powerful and robust Elixir-based AI agent orchestration framework. By carefully defining the integration points and leveraging the strengths of both Elixir and `pydantic-ai`, we can create a system that is both powerful and maintainable.
