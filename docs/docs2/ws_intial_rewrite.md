# Synapse Pydantic-AI Integration Files

This document provides an overview of all files created for the Synapse Pydantic-AI integration.

## Core Components

### Elixir Components

1. **Agent Process** (`apps/synapse_core/lib/synapse_core/pydantic_agent_process.ex`)
   - Core component for managing AI agents
   - Handles lifecycle and message passing
   - Manages state and error handling

2. **HTTP Client** (`apps/synapse_core/lib/synapse_core/pydantic_http_client.ex`)
   - Handles communication with Python agents
   - Built on Finch for better performance
   - Supports both sync and streaming requests

3. **Tool Registry** (`apps/synapse_core/lib/synapse_core/pydantic_tool_registry.ex`)
   - Manages and executes tools
   - Handles tool validation
   - Provides tool discovery

4. **Supervisor** (`apps/synapse_core/lib/synapse_core/pydantic_supervisor.ex`)
   - Manages component lifecycles
   - Provides fault tolerance
   - Handles dynamic agent creation

5. **JSON Codec** (`apps/synapse_core/lib/synapse_core/pydantic_json_codec.ex`)
   - Handles JSON encoding/decoding
   - Manages datetime serialization
   - Converts string keys to atoms safely

### Python Components

1. **Agent Wrapper** (`apps/synapse_python/src/synapse_python/pydantic_agent_wrapper.py`)
   - FastAPI service for pydantic-ai agents
   - Handles HTTP endpoints
   - Manages agent lifecycle

2. **Translation Agent** (`apps/synapse_python/src/synapse_python/agents/translation_agent.py`)
   - Example agent implementation
   - Demonstrates basic agent setup
   - Shows tool usage

3. **Research Agent** (`apps/synapse_python/src/synapse_python/agents/research_agent.py`)
   - Complex agent example
   - Shows tool chaining
   - Demonstrates streaming

## Documentation

1. **Main Integration Guide** (`docs/pydantic_integration.md`)
   - Complete integration overview
   - Usage examples
   - Best practices

2. **Component Documentation**
   - Agent Process (`docs/components/pydantic_agent_process.md`)
   - HTTP Client (`docs/components/pydantic_http_client.md`)
   - Tool Registry (`docs/components/pydantic_tool_registry.md`)

## Tests

1. **Integration Tests** (`apps/synapse_core/test/integration/pydantic_integration_test.exs`)
   - Complete system testing
   - Covers all components
   - Tests error cases

2. **Python Tests** (`apps/synapse_python/tests/test_pydantic_agent_wrapper.py`)
   - Tests Python components
   - Covers HTTP endpoints
   - Tests agent functionality

## Key Features

1. **Type Safety**
   - Strong typing in both Elixir and Python
   - Pydantic models for validation
   - Clear error hierarchies

2. **Message Flow**
   - Direct mapping between Elixir and pydantic-ai
   - Proper streaming support
   - Structured error handling

3. **State Management**
   - Clear agent lifecycle
   - Proper agent registry
   - Clean shutdown handling

4. **Tool Support**
   - Flexible tool registration
   - Parameter validation
   - Async tool support

5. **Monitoring**
   - Telemetry integration
   - Resource tracking
   - Error logging

## Getting Started

1. Add components to your supervision tree:
```elixir
children = [
  SynapseCore.PydanticSupervisor
]

Supervisor.start_link(children, strategy: :one_for_one)
```

2. Create and run an agent:
```elixir
config = %{
  name: "my_agent",
  python_module: "translation_agent",
  model: "gemini-1.5-pro",
  system_prompt: "You are a helpful assistant."
}

{:ok, pid} = SynapseCore.PydanticSupervisor.start_agent(config)
```

3. Use the agent:
```elixir
{:ok, result} = SynapseCore.PydanticAgentProcess.run(
  "my_agent",
  "Translate 'Hello' to Spanish"
)
