# Direction


You're right to bring up the question of a complete wrapper for `pydantic-ai`. While our initial focus has been on an integration where `pydantic-ai` agents run in separate Python processes, it's worth exploring how close we can get to a "complete wrapper" that allows us to write most of the agent logic in Elixir.

**Challenges of a Complete Wrapper:**

1. **Dynamic Nature of `pydantic-ai`:** `pydantic-ai` relies heavily on Python's dynamic features, such as decorators, runtime type checking, and dynamic function calls. Replicating this behavior entirely in Elixir would be challenging and might not be idiomatic.
2. **Pydantic's Core Role:** Pydantic is fundamental to how `pydantic-ai` works. It handles schema definition, data validation, and JSON serialization/deserialization. While Elixir has libraries for these tasks, they might not offer the same level of integration and seamlessness as Pydantic.
3. **LLM Interactions:** `pydantic-ai` directly interacts with various LLM APIs (OpenAI, Anthropic, etc.). A complete wrapper would need to provide Elixir equivalents for these interactions, which might involve writing Elixir clients for these APIs or using existing ones if available.
4. **Streaming:** Handling streamed responses from LLMs in a way that's idiomatic to both Elixir and the specific LLM's API would require careful design.

**How Close Can We Get to a Complete Wrapper?**

Despite these challenges, we can get pretty close to a complete wrapper by focusing on these areas:

1. **Agent Definition and Workflow in Elixir:**
    *   We can define agent configurations, including the model, system prompt, tools, and result type, using Elixir data structures (e.g., structs, maps, or a DSL).
    *   We can implement workflow logic (how agents interact, message routing) entirely in Elixir using GenServers and message passing.

2. **Schema Translation:**
    *   We can develop a mechanism to translate between Pydantic models (or their JSON schemas) and Elixir data structures. This might involve:
        *   Generating Elixir structs from Pydantic models.
        *   Using a library like `jason_schema` to validate data against JSON schemas in Elixir.
        *   Potentially creating custom Elixir types that mirror Pydantic's types (e.g., `String`, `Integer`, `Boolean`, `List`, `Dict`).

3. **Tool Definition and Execution:**
    *   This is the most challenging part. We have a few options:
        *   **Limited Elixir Tools:** For simple tools, we could define them entirely in Elixir and execute them directly within the Elixir agent process.
        *   **Hybrid Approach:** Define tools in Elixir, but when they need to call Python code (e.g., for interacting with a specific Python library), use a controlled mechanism to invoke a Python function. This could be via HTTP, gRPC, or even a more lightweight approach like [Erlang Ports](https://www.erlang.org/doc/tutorial/c_port.html) (for very simple interactions).
        *   **Python Stub Generation:** We could potentially generate Python stub code from the Elixir tool definitions. This code would handle receiving the tool call from Elixir, invoking the corresponding `pydantic-ai` tool in Python, and sending the result back.
    *   We need a way to map Elixir tool definitions to Python functions. This could be done via naming conventions, configuration files, or a more sophisticated registration mechanism.

4. **LLM Interaction:**
    *   We could potentially use existing Elixir libraries for interacting with LLMs if they become available and mature enough.
    *   Alternatively, we could create a thin Python wrapper around the LLM APIs that's specifically designed for communication with our Elixir orchestrator. This wrapper would handle the low-level details of the API calls, while the Elixir side would manage the higher-level agent logic.

**Proposed Approach for a "Near-Complete" Wrapper:**

1. **Focus on Elixir Orchestration:**  Continue with the current approach of using Elixir for agent management, workflow definition, and message routing.
2. **Enhanced Schema Translation:** Develop a more robust schema translation layer to handle a wider range of Pydantic models and data types.
3. **Hybrid Tool Execution:**
    *   Allow defining simple tools in Elixir.
    *   For complex tools or those requiring Python libraries, provide a mechanism to call out to Python functions (e.g., via HTTP, gRPC, or Ports).
    *   Potentially explore generating Python stubs for tools defined in Elixir.
4. **Thin Python LLM Wrapper:** Create a Python module (`axon_python.llm_wrapper` or similar) that exposes a simplified interface for interacting with LLMs. This module would be called by the `pydantic-ai` agents in Python, but its API would be designed for easy use from Elixir.

**Example (Illustrative):**

**Elixir Agent Definition:**

```elixir
defmodule MyApp.AgentWorkflow do
  use Axon.Workflow

  agent(:my_agent,
    model: "openai:gpt-4o",
    system_prompt: "You are a helpful assistant.",
    tools: [
      %{
        name: "add_numbers",
        description: "Adds two numbers.",
        handler: {:elixir, &MyElixirTools.add_numbers/2} # Elixir function
      },
      %{
        name: "call_python_tool",
        description: "Calls a Python tool.",
        handler: {:python, module: "my_python_tools", function: "do_something"}
      }
    ],
    result_type: %{
      result: :integer
    }
  )
end

defmodule MyElixirTools do
  def add_numbers(a, b), do: a + b
end
```

**Python LLM Wrapper (`axon_python/src/axon_python/llm_wrapper.py`):**

```python
# Simplified example
from openai import OpenAI

def get_completion(model: str, messages: list, tools: list | None = None) -> str:
    client = OpenAI() # Or get from env, etc.
    response = client.chat.completions.create(
        model=model,
        messages=messages,
        tools=tools,
    )
    return response.choices[0].message.content
```

**Elixir Agent Process (Simplified):**

```elixir
defmodule AxonCore.AgentProcess do
  # ...

  def handle_call({:run, request}, _from, state) do
    # ...

    case tool_call do
      {:elixir, function} ->
        # Call the Elixir function directly
        result = function.(args)
        send_result_back_to_python(state.python_pid, result)

      {:python, module: module, function: function} ->
        # Send a request to the Python side to execute the function
        send_request_to_python(state.python_pid, module, function, args)

      _ ->
        # Handle unknown tool type
        send_error_to_python(state.python_pid, "Unknown tool type")
    end

    # ...
  end

  # ...
end
```

**Discussion:**

*   This approach allows us to write most of the agent logic in Elixir, leveraging its strengths for concurrency and fault tolerance.
*   We can still use `pydantic-ai`'s core features, like structured output generation and the tool-calling mechanism.
*   The complexity of interacting with LLM APIs is largely encapsulated within the Python wrapper.
*   The choice between HTTP, gRPC, or Ports for communication between Elixir and Python can be made based on performance and complexity considerations.

**Conclusion:**

While a 100% "pure Elixir" wrapper for `pydantic-ai` might be impractical or even undesirable, we can create a system where Elixir plays the dominant role in agent orchestration and logic, while still leveraging `pydantic-ai` and the Python ecosystem for LLM interactions and specific libraries. This hybrid approach allows us to build a powerful and flexible AI agent framework that takes advantage of the best of both worlds.





You're right to emphasize the deep integration with Pydantic in `pydantic-ai` and the challenges and opportunities that presents for our Elixir-centric Axon framework. Let's delve into those aspects.

**1. Pydantic Integration in `pydantic-ai`**

Pydantic is not just a peripheral component of `pydantic-ai`; it's woven into its core design and functionality in several ways:

*   **Schema Definition:** Pydantic models (or `TypedDicts` in some cases) are used to define the structure of:
    *   **Agent input:** The types of `deps` (dependencies) an agent can receive.
    *   **Tool parameters:** The arguments that tools expect, including their types and descriptions. This information is used to generate JSON Schema, which is then passed to the LLM.
    *   **Result type:** The structure of the data the agent is expected to return.
*   **Data Validation:** Pydantic's validation engine is used extensively to:
    *   Validate the arguments passed to tools against their defined schemas.
    *   Validate the final result returned by the agent against the `result_type`.
    *   Handle validation errors by optionally triggering retries or raising exceptions.
*   **JSON Schema Generation:** `pydantic-ai` relies on Pydantic's ability to generate JSON Schema from models. These schemas are crucial for:
    *   Communicating tool definitions to LLMs that understand function calling via JSON Schema.
    *   Guiding the structured output generation (e.g., when using models like `gemini-1.5-pro` with a specified `result_type`).
*   **Serialization/Deserialization:** Pydantic handles the conversion between Python objects and JSON when interacting with LLMs.

**Challenges for a "Complete Wrapper":**

The deep integration with Pydantic poses these challenges for a complete Elixir wrapper:

*   **Schema Representation:** We need a way to represent Pydantic-like schemas in Elixir. While we can use JSON Schema, directly mirroring Pydantic's rich type system (including custom validators, constraints, etc.) might be difficult.
*   **Validation Logic:** Replicating Pydantic's validation logic in Elixir would be a significant undertaking. We'd either need to find an Elixir library with comparable capabilities or implement a subset of Pydantic's validation features.
*   **Dynamic Function Calls:** `pydantic-ai` uses Python's dynamic features to call tool functions based on their names and the arguments provided by the LLM. We'd need to implement a similar mechanism in Elixir, which might involve using macros or code generation.
*   **Error Handling:** `pydantic-ai`'s error handling (especially for retries) is tightly coupled with Pydantic's `ValidationError`. We'd need to map these errors to Elixir exceptions or error tuples in a meaningful way.

**2. Limitations Due to Python-Specific Generalizations and Concurrency**

Here are some areas where `pydantic-ai`'s Python-specific features or assumptions about concurrency might limit a direct, one-to-one mapping to Elixir:

*   **Decorators:** `pydantic-ai` uses decorators (`@agent.tool`, `@agent.system_prompt`, etc.) extensively. While Elixir has macros, they don't map directly to Python decorators. We'd need to find an alternative way to register tools, system prompts, and result validators.
*   **`RunContext`:** The `RunContext` object in `pydantic-ai` provides contextual information to tools and system prompt functions. While we can pass a similar context object from Elixir, the tight integration with type hints in Python might be hard to replicate.
*   **`asyncio`:** `pydantic-ai` relies on `asyncio` for asynchronous operations. While Elixir has its own concurrency model based on lightweight processes, directly mapping `asyncio` patterns to Elixir might not be seamless. We'll need to use Elixir's approach to concurrency (e.g., `Task`, `GenServer`).
*   **Pythonic Idioms:** `pydantic-ai` uses many Python-specific idioms (e.g., exceptions for control flow, dynamic attribute access) that don't have direct equivalents in Elixir.

**Detailed Integration Options for Elixir:**

Given these challenges, here's a more detailed look at how we can achieve a deep integration, focusing on the key areas:

**a) Agent Definition and Configuration:**

*   **Elixir DSL or Data Structures:** We can create a DSL (Domain Specific Language) in Elixir for defining agents and their configurations. Alternatively, we can use Elixir's built-in data structures (maps, structs) to represent agent definitions.
*   **Example (using a struct):**

    ```elixir
    defmodule AgentConfig do
      defstruct [
        name: nil,
        model: nil,
        system_prompt: nil,
        tools: [],
        result_type: nil, # Could be a JSON Schema or a custom Elixir type
        retries: 1,
        result_retries: nil,
        end_strategy: :early
      ]
    end
    ```

**b) Schema Translation and Validation:**

*   **JSON Schema as an Intermediary:** We can use JSON Schema as a common language for representing data structures.
    *   **Elixir -> Python:** When defining an agent, we can convert the Elixir representation of the schema into a JSON Schema. This schema will be sent to the Python side during agent initialization.
    *   **Python -> Elixir:** When a Python agent returns structured data, we can use a JSON Schema validator in Elixir to validate the response against the expected schema.
*   **Libraries:**
    *   **Elixir:** `jason_schema` or `ex_json_schema` for JSON Schema validation.
    *   **Python:** Pydantic's built-in JSON Schema generation capabilities.
*   **Challenges:**
    *   Mapping Pydantic's rich type system (including custom validators) to JSON Schema and then to Elixir types will require careful design.
    *   We might need to extend the JSON Schema standard or use annotations to capture Pydantic-specific features.

**c) Tool Definition and Execution:**

*   **Hybrid Approach:**
    *   **Simple Elixir Tools:** For tools that can be implemented purely in Elixir, define them as Elixir functions.
    *   **Python Tools:** For tools that require Python libraries or complex logic, define them in Python using `pydantic-ai` and expose them via the `agent_wrapper.py` API.
*   **Tool Registration:**
    *   **Elixir Side:**  When defining an agent in Elixir, specify the tools it can use. For Python tools, provide the necessary information (module, function name) to invoke them via HTTP (or gRPC).
    *   **Python Side:** `agent_wrapper.py` will be responsible for mapping the tool names received from Elixir to the actual Python functions.
*   **Execution:**
    *   **Elixir Tools:** The Elixir agent process will execute these directly.
    *   **Python Tools:** The Elixir agent process will send an HTTP request to `agent_wrapper.py` to execute the tool.

**d) LLM Interaction:**

*   **Thin Python Wrapper:** Create a Python module (`llm_wrapper.py`) that provides a simplified interface to LLM APIs. This module will be used by the `pydantic-ai` agents.
*   **Example (`llm_wrapper.py`):**

    ```python
    from openai import AsyncOpenAI

    async def get_completion(model: str, messages: list, tools: list | None = None):
        client = AsyncOpenAI()  # Or configure based on environment variables
        response = await client.chat.completions.create(
            model=model,
            messages=messages,
            tools=tools,
        )
        return response.choices[0].message.content

    async def get_streamed_completion(model: str, messages: list, tools: list | None = None):
      client = AsyncOpenAI()
      stream = await client.chat.completions.create(
          model=model,
          messages=messages,
          tools=tools,
          stream=True,
      )
      async for chunk in stream:
          yield chunk.choices[0].delta.content or ""
    ```

*   **Elixir Control:** The Elixir side will pass the necessary parameters (model name, messages, etc.) to the Python agent, which will then use `llm_wrapper.py` to interact with the LLM.

**e)  gRPC vs HTTP:**

*   While gRPC offers performance benefits, you are right to assume the bottleneck will be model interactions.
*   We can gain significant ground in erlang/elixir by managing the state of each of these concurrent processes.

**Example Integration with `bank_support.py`:**

Let's see how we can integrate the `bank_support.py` example into Axon, illustrating the concepts we've discussed.

**1. Python Agent (`axon_python/src/axon_python/agents/bank_support_agent.py`):**

```python
from dataclasses import dataclass

from pydantic import BaseModel, Field
from pydantic_ai import Agent
# Assume DatabaseConn is replaced with a version that can be initialized with data from Elixir
from .db import DatabaseConn

@dataclass
class SupportDependencies:  # (3)!
    customer_id: int
    db: DatabaseConn  # (12)!

class SupportResult(BaseModel):  # (13)!
    support_advice: str = Field(description='Advice returned to the customer')
    block_card: bool = Field(description="Whether to block the customer's card")
    risk: int = Field(description='Risk level of query', ge=0, le=10)

# Get model from environment variable
import os
model_name = os.environ.get("AXON_PYTHON_AGENT_MODEL")

support_agent = Agent(  # (1)!
    model_name,  # (2)!
    # Pass the dependency and result types to the agent
    result_type=SupportResult,
    system_prompt=(  # (4)!
        'You are a support agent in our bank, give the '
        'customer support and judge the risk level of their query.'
    ),
)
```

**2. Elixir Agent Definition:**

```elixir
defmodule MyApp.AgentWorkflow do
  use Axon.Workflow

  agent(:bank_support_agent,
    module: "bank_support_agent",
    model: {:system, "AXON_PYTHON_AGENT_MODEL"},
    system_prompt: "You are a support agent in our bank...",
    tools: [
      %{
        name: "customer_balance",
        description: "Returns the customer's current account balance.",
        handler: {:python, module: "bank_support_agent", function: "customer_balance"}
      }
    ],
    result_type: %{
      support_advice: :string,
      block_card: :boolean,
      risk: :integer
    },
    deps: %{
      db_host: "localhost",
      db_port: 5432,
      # ... other DB connection details
    }
  )

  # ... workflow definition ...
end
```

**3. Elixir `AgentProcess` (Simplified):**

```elixir
defmodule AxonCore.AgentProcess do
  use GenServer

  # ...

  def handle_call({:run, prompt, history}, _from, state) do
    # 1. Translate Elixir config to JSON for Python
    request_data = %{
      prompt: prompt,
      message_history: history,
      # ... other data, including tool definitions, result_type schema, etc. ...
    }

    # 2. Send HTTP request to Python agent (or gRPC in the future)
    case HTTPClient.post(state.agent_endpoint, [], JSONCodec.encode(request_data)) do
      {:ok, response} ->
        # 3. Process response, potentially handle streaming, validation, etc.
        # 4. Return result or route to another agent
        {:reply, {:ok, result}, state}
      {:error, reason} ->
        # Handle error
        {:reply, {:error, reason}, state}
    end
  end

  # ...
end
```

**4. Python `agent_wrapper.py` (Simplified):**

```python
from fastapi import FastAPI, HTTPException
# ... (import bank_support_agent and other necessary modules)

app = FastAPI()

# Assuming agent_id is passed in the URL or a header
@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request_data: dict):
    try:
        # Get the agent instance based on agent_id
        agent = agent_instances[agent_id]

        # Pass data to the agent, handling dependencies if necessary
        result = agent.run_sync(
            request_data["prompt"],
            message_history=request_data.get("message_history"),
            # How to handle deps?
            # - Pass them in the request from Elixir?
            # - Initialize them here based on agent configuration?
            # deps=...,
        )

        return {"result": result.data, "usage": result.usage()}
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

**Key Points:**

*   **Elixir is in Control:** The Elixir side defines the agent, its configuration, and the overall workflow.
*   **Schema Translation:** We're using a simplified representation of the `result_type` in Elixir (`%{support_advice: :string, ...}`). A more robust solution would involve generating JSON Schema from Pydantic models and using that to validate data on both sides.
*   **Dependency Injection:** The example shows how dependencies (like `db_host`, `db_port`) can be passed from Elixir to the Python agent. We'd need a more general mechanism for passing arbitrary dependencies.
*   **Error Handling:** The code includes basic error handling, but this would need to be expanded to handle different types of errors (e.g., `ModelRetry`, validation errors) and potentially propagate them back to Elixir.
*   **HTTP Communication:** The example uses HTTP for simplicity, but it could be replaced with gRPC.

This more in-depth analysis should give you a clearer path towards building a powerful Elixir-based agent orchestration framework that leverages the strengths of both Elixir/OTP and `pydantic-ai`. Remember to iterate and refine the design as you implement and test the system. I'm here to help with any further questions!
Okay, let's perform a critical analysis of the project's current state and propose the ideal level of integration between `pydantic-ai` and our Elixir system, Axon, focusing on the value that `pydantic-ai` brings and how to leverage it effectively.

**Project State and Assumptions:**

*   **Axon as the "God App":**  Elixir/OTP is the core of our system. Axon is designed to be an Elixir-first AI agent orchestration framework.
*   **Leveraging `pydantic-ai`:** We want to use `pydantic-ai` to handle interactions with LLMs and benefit from its features like structured output, tool calling, and message management.
*   **No Elixir-Based Process/Container Management:** Initially, we won't use Elixir to manage Python virtual environments, processes, or Docker containers. We'll assume the Python environment with `pydantic-ai` is set up separately.
*   **HTTP Communication (for now):** We're starting with HTTP for communication between Elixir and Python for simplicity.
*   **Focus on Integration Value:** We want to identify the specific problems that `pydantic-ai` solves and integrate those solutions into Axon without unnecessary overhead.

**Critical Analysis of `pydantic-ai`'s Strengths:**

1. **Structured Output Generation:** `pydantic-ai` excels at using Pydantic models to define and enforce structured output from LLMs. This is a core value proposition.
2. **Tool Calling/Function Calling:** `pydantic-ai` provides a convenient way to define tools (functions) that LLMs can call, including automatic generation of JSON Schema for tool parameters.
3. **Message Management:** `pydantic-ai` handles the construction of messages for the LLM, including system prompts, user prompts, tool calls, and tool returns. It also manages message history.
4. **Retry Mechanism:** `pydantic-ai` has a built-in retry mechanism to handle validation errors and model-specific issues.
5. **Model Abstraction:** `pydantic-ai` provides a relatively consistent interface across different LLM providers (OpenAI, Anthropic, Gemini, etc.), although some model-specific differences still exist.
6. **Asynchronous and Streaming Support:** `pydantic-ai` supports both synchronous and asynchronous (streaming) interactions with LLMs.

**Potential Drawbacks of a Naive Integration:**

*   **Redundancy:** If we're not careful, we might end up reimplementing features in Elixir that `pydantic-ai` already provides, leading to unnecessary complexity and maintenance overhead.
*   **Performance Overhead:** Excessive communication between Elixir and Python can introduce latency, especially if we're not using an optimized protocol like gRPC.
*   **Tight Coupling:** We need to avoid overly tight coupling between Axon and `pydantic-ai`. Ideally, we should be able to swap out the Python component with other solutions if needed.

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
