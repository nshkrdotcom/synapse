# Axon: Elixir-Powered AI Agent Orchestration

## Overview

**Axon** is a robust and scalable AI agent orchestration framework built on the power of Elixir and the BEAM VM. It leverages the strengths of **Erlang/OTP** for concurrency, fault tolerance, and distributed computing to manage and coordinate a network of AI agents. While providing first-class integration with Python, Axon is designed to support polyglot architectures, empowering developers to build sophisticated, multi-agent systems that harness the best of both worlds.

Axon draws inspiration from `pydantic-ai`, a Python library that combines the structured data validation of Pydantic with the dynamic capabilities of LLMs. However, Axon is not merely a port; it's a reimagining of agent orchestration in the context of Elixir's unique capabilities.

## Core Principles

*   **Elixir-First Orchestration:** Elixir's OTP principles (supervision trees, GenServers, message passing) form the foundation of Axon's agent management.
*   **Polyglot Design:** Seamlessly integrate Python agents (built with `pydantic-ai` or other frameworks) and potentially other languages, taking advantage of their specific strengths.
*   **Scalability and Fault Tolerance:** Leverage the BEAM VM's inherent capabilities to build systems that can scale effortlessly and gracefully handle failures.
*   **Developer Ergonomics:** Provide a clean, Elixir-idiomatic API for defining, managing, and interacting with agents.
*   **Extensibility:** Allow for the integration of various LLMs, vector databases, and other AI tools through a modular architecture.
*   **Observability:** Offer robust monitoring, logging, and tracing capabilities to understand the behavior of complex agent interactions.

## Structure

Axon follows an umbrella project structure, similar in style to `cf_ex`, with the following applications:

*   **`axon_core`:** The core Elixir library. It contains modules for:
    *   Agent supervision and lifecycle management.
    *   HTTP communication with Python (and potentially other) agents.
    *   JSON encoding/decoding for data exchange.
    *   Common typespecs and utilities.
*   **`axon`:** A Phoenix application providing a web interface and API for interacting with the Axon system. This component will make heavy use of our `cf_ex` library for improved Cloudflare integration.
*   **`axon_python`:** A dedicated application for managing the integration with Python-based agents. It includes:
    *   A FastAPI wrapper (`agent_wrapper.py`) to expose `pydantic-ai` agents as HTTP endpoints.
    *   Example `pydantic-ai` agent implementations.
    *   Elixir modules for spawning and communicating with Python processes.

## Installation

```elixir
def deps do
  [
    {:axon_core, in_umbrella: true},
    {:axon, in_umbrella: true},
    {:axon_python, in_umbrella: true},
    {:jason, "~> 1.4"}, # Or another JSON library
    {:req, "~> 0.4"} # Or another HTTP client
    # Consider adding Finch for improved performance later
    # Optional:
    # {:ecto_sql, "~> 3.9"}, # If using Ecto for persistence
    # {:postgrex, ">= 0.0.0"} # If using Postgres
  ]
end
```

## Usage (Conceptual Examples)

**Defining an Agent Workflow in Elixir:**

```elixir
# lib/my_app/agent_workflow.ex

defmodule MyApp.AgentWorkflow do
  use Axon.Workflow

  agent(:python_agent_1, 
      module: "python_agent_1", 
      model: "openai:gpt-4o",
      system_prompt: "You are a helpful assistant that translates English to French.",
    tools: [
        %{
        name: "some_tool",
        description: "A simple tool that takes a string and an integer as input.",
        parameters: %{
            "type" => "object",
            "properties" => %{
            "arg1" => %{"type" => "string"},
            "arg2" => %{"type" => "integer"}
            },
            "required" => ["arg1", "arg2"]  # If both are required
        },
        handler: {:python, module: "example_agent", function: "some_tool"}
        }
    ],
      result_type: %{
        translation: :string
      },
      retries: 3
      )

  agent(:python_agent_2,
    module: "python_agent_2",
    model: "gemini-1.5-flash",
    system_prompt: "You are a summarization expert.",
    deps: %{api_key: "your_gemini_api_key"} # Example of passing dependencies
  )

  # Define connections/message routing between agents
  flow do
    python_agent_1 |> python_agent_2
  end
end
```

**Interacting with Agents via the Phoenix API:**

```bash
# Send a request to `python_agent_1`
curl -X POST http://localhost:4000/agents/python_agent_1/run_sync \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello, how are you?"}'

# Example response
# {"status": "success", "result": {"translation": "Bonjour, comment ça va?"}, "usage": {...}}
```

**Example `pydantic-ai` Agent in Python:**

```python
# apps/axon_python/lib/axon_python/agents/python_agent_1.py
from pydantic import BaseModel
from pydantic_ai import Agent

class Input(BaseModel):
    prompt: str

class Output(BaseModel):
    translation: str

agent = Agent(
    model="openai:gpt-4o",  # Or read from environment variable set by Elixir
    result_type=Output,
    system_prompt="You are a helpful assistant that translates English to French.",
)
```

## Key Features and Considerations

*   **HTTP-Based Communication:** Initially using HTTP with JSON for simplicity and ease of debugging.
*   **Pydantic-AI Integration:** Leverages the power of `pydantic-ai` for agent definition and LLM interaction on the Python side.
*   **Elixir/OTP for Orchestration:** Utilizes Elixir's concurrency model and OTP principles for robust agent management.
*   **Agent Lifecycle Management:** Elixir supervisors handle starting, stopping, and restarting Python agent processes.
*   **Message Routing:** Elixir orchestrates the flow of messages between agents based on a defined workflow.
*   **Configuration from Elixir:** All agent configuration is managed by Elixir and passed to the Python side.
*   **Schema Validation:** Uses JSON Schema (or a similar mechanism) to define input/output schemas for agents and perform validation.
*   **Extensible Design:** Allows for future integration of other LLMs, tools, and communication protocols (e.g., gRPC).
*   **Streaming Support:** Designed with streaming in mind, although the initial implementation might use polling for simplicity.

## Why "Axon"?

The name "Axon" combines the "Ax" from "Elixir" with "on" to signify agents that are "on" and connected. It also evokes the biological axon, which transmits signals in a neural network, reflecting the framework's role in connecting and orchestrating AI agents.

## Conclusion

Axon aims to be a unique and powerful addition to the AI ecosystem, combining the strengths of Elixir/OTP with the flexibility and rich ecosystem of Python and `pydantic-ai`. This README provides a starting point for the project, outlining the core concepts, structure, and initial design choices. As development progresses, the design and implementation details will be further refined. We will prioritize a simple and robust HTTP-based integration, allowing us to deliver a functional system quickly while keeping our options open for future performance optimizations and advanced features.
