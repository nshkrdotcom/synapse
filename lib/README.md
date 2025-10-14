# Synapse Core



## Synapse Core: Pydantic Integration

This module provides the core functionality for integrating Synapse with `pydantic-ai` and other Python-based AI agent systems. It handles the communication, schema translation, and tool definition mapping between the Elixir and Python worlds.

**Key Components:**

*   **`SynapseCore.AgentProcess`:** A GenServer that manages the lifecycle of a Python agent process and facilitates communication via HTTP.
*   **`SynapseCore.HTTPClient`:**  A thin wrapper around an HTTP client library (e.g., `req` or `Finch`) to make requests to Python agents.
*   **`SynapseCore.JSONCodec`:** Handles JSON encoding and decoding using `Jason`.
*   **`SynapseCore.SchemaUtils`:** Provides utilities for translating between Elixir data structures and JSON Schema, enabling schema validation across languages.
*   **`SynapseCore.ToolUtils`:**  Manages the definition and execution of tools. It supports both Elixir-native tools and tools that are implemented in Python and called remotely.

**Design Principles:**

*   **Elixir as the Orchestrator:** Elixir/OTP is the primary driver for agent management, workflow execution, and error handling.
*   **`pydantic-ai` as a Service:** Python agents, built using `pydantic-ai`, are treated as external services that Elixir interacts with.
*   **Schema-Driven Communication:** JSON Schema is used as the common language for defining data structures and validating messages exchanged between Elixir and Python.
*   **Flexibility:** The design allows for both synchronous and asynchronous (streaming) communication, and it can be extended to support other communication protocols (e.g., gRPC) in the future.

**Tool Handling (`SynapseCore.ToolUtils`)**

`SynapseCore.ToolUtils` plays a crucial role in bridging the gap between Elixir's type system and the way tools are defined in `pydantic-ai`.

*   **`to_json_schema/1`:** Converts an Elixir tool definition (including name, description, and parameters) into a JSON Schema representation that can be understood by `pydantic-ai`.
*   **`call_elixir_tool/2`:** Provides a mechanism to call Elixir functions dynamically, enabling the implementation of Elixir-based tools.

**Schema Management (`SynapseCore.SchemaUtils`)**

This module is responsible for:

*   **`elixir_to_json_schema/1`:** Converts Elixir type information (currently quite basic) into a JSON Schema. This is a simplified implementation and will need to be extended to support a wider range of types and Pydantic features.
*   **`validate/2`:** Validates data against a given JSON Schema. This could leverage a library like `jason_schema` or a custom implementation tailored to our needs.

**Future Considerations:**

*   **Advanced Schema Mapping:** Develop a more sophisticated mapping between Pydantic models and Elixir data structures, potentially using a dedicated library or creating a custom DSL.
*   **gRPC Support:** Implement gRPC as an alternative communication protocol for improved performance.
*   **Python Stub Generation:** Explore the possibility of automatically generating Python stub code for Elixir-defined tools to improve type safety and developer experience on the Python side.
*   **Enhanced Error Handling:** Implement detailed error reporting and potentially a retry mechanism that's integrated with Elixir's supervision system.
*   **Security:** Add authentication and authorization mechanisms to secure the communication between Elixir and Python agents.

This README provides an overview of the `SynapseCore.PydanticIntegration` module and its role in bridging the Elixir and Python worlds within the Synapse framework.