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
 



 Okay, let's review our conversation and create a complete file tree for the Axon project based on our current design parameters, including all necessary files while excluding irrelevant ones.

**Core Principles and Design Choices (Recap):**

*   **Elixir as the Orchestrator:** Axon is an Elixir-first framework, leveraging OTP for supervision, concurrency, and fault tolerance.
*   **`pydantic-ai` Integration:** We're using `pydantic-ai` in Python to handle LLM interactions, structured output generation, and tool calling.
*   **HTTP Communication:** We've chosen HTTP with JSON for communication between Elixir and Python agents (for now).
*   **Simplified Python Wrapper:** `agent_wrapper.py` acts as a thin layer between Elixir and `pydantic-ai` agents, handling requests and responses.
*   **Elixir-Based Configuration:** Agent configurations, including model names, system prompts, tools, and result types, are defined in Elixir.
*   **Schema Translation:** We'll need a mechanism to translate between Elixir data structures and JSON Schema for data validation.
*   **Error Handling, Logging, and Monitoring:** Primarily managed by Elixir, with Python agents reporting errors and logs in a structured format.
*   **Development Environment:**  We're targeting a developer-friendly setup with `venv` for Python and `asdf` for Erlang/Elixir.

**Talking Through the File Structure:**

1. **Umbrella Structure:** We're following the established pattern from `cf_ex` of using an Elixir umbrella project. This is good for organizing the different components.

2. **`apps/axon_core`:** This is the core of the Elixir logic.
    *   **`supervisor.ex`:**  Supervises agent processes.
    *   **`agent_registry.ex`:**  Likely using `Registry` to track agent processes.
    *   **`http_client.ex`:** Handles making HTTP requests to Python agents. We might use `req` or `Finch` here.
    *   **`json_codec.ex`:**  Handles JSON encoding/decoding, probably using `Jason`.
    *   **`types.ex`:**  Defines common typespecs for the project.
    *   **`agent_process.ex`:** The `GenServer` that manages a single Python agent process, handles communication, and implements error handling and logging.
    *   **`tool_utils.ex`:**  (New) A module to encapsulate logic related to tool definition translation and potentially dynamic function calls for Elixir-based tools.
    *   **`schema_utils.ex`:** (New) A module to handle schema translation and validation, potentially using `jason_schema` or a custom implementation.

3. **`apps/axon`:** A Phoenix application for a web interface and API.
    *   **`controllers/`, `channels/`, `templates/`, `views/`:**  Standard Phoenix directories for controllers, channels, templates, and views.
    *   **`axon.ex`, `axon_web.ex`, `router.ex`:** Standard Phoenix application and routing files.

4. **`apps/axon_python`:**
    *   **`pyproject.toml`, `poetry.lock`:**  Poetry project files for managing Python dependencies.
    *   **`src/axon_python/__init__.py`:**  Make `axon_python` a package.
    *   **`src/axon_python/agent_wrapper.py`:** The FastAPI application that wraps `pydantic-ai` agents. This will include error handling and logging logic to send information back to Elixir.
    *   **`src/axon_python/agents/`:**  A directory for storing `pydantic-ai` agent code (e.g., `example_agent.py`, `bank_support_agent.py`).
    *   **`src/axon_python/llm_wrapper.py`:** (New) A module providing a simplified interface for interacting with LLMs, abstracting away some of the `pydantic-ai` and library-specific details.
    *   **`scripts/start_agent.sh`:**  A shell script to start a Python agent process, activating the virtual environment and setting environment variables.
    *   **`test/`:** Python tests.
    *   **`mix.exs`:** While this will be an Elixir umbrella application, it will manage a python project.

5. **`lib/axon.ex`:** Main entry point for the Axon application.

6. **`rel/`:** Release configuration (if needed for deployment).

7. **`config/`:** Elixir configuration files.

8. **`mix.exs`:** Umbrella project definition.

9. **`README.md`:** Project documentation.

10. **`.gitignore`:**  Ignore virtual environments, build artifacts, etc.

11. **`start.sh`:** Top-level startup script for development.
 













# Error Handling, Logging, Monitoring, Testing

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
