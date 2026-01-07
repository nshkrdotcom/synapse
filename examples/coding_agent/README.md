# CodingAgent

A multi-model coding agent example that orchestrates Claude, Codex, and Gemini
using the Synapse workflow engine.

## Overview

This example demonstrates:

- **Multi-provider orchestration**: Route tasks to the best provider based on task type
- **Synapse workflow integration**: Use the workflow engine for execution, persistence, and audit trails
- **Provider-specific prompting**: Optimized prompts for each AI model
- **Multiple execution modes**: Single provider, parallel, and cascade (fallback)

## Quick Start

```bash
# Install dependencies
mix deps.get

# Set API keys (at least one)
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="..."

# Run a task
mix coding_agent "Write a function to parse JSON in Elixir"
```

## Usage

### CLI

```bash
# Auto-routes based on task type
mix coding_agent "Write a GenServer for caching"

# Specify provider explicitly
mix coding_agent "Review this code" --provider codex

# Parallel execution (all providers)
mix coding_agent "Analyze this algorithm" --parallel

# Cascade (tries providers until one succeeds)
mix coding_agent "Fix this bug" --cascade

# With code context from file
mix coding_agent "Refactor this module" --file lib/my_module.ex

# With inline context
mix coding_agent "Explain this" --context "def foo, do: :bar" --language elixir
```

### Programmatic

```elixir
# Simple execution
{:ok, result} = CodingAgent.execute("Write a GenServer for caching")

# Specific provider
{:ok, result} = CodingAgent.execute("Review this code",
  provider: :codex,
  context: code_string
)

# Parallel execution
{:ok, result} = CodingAgent.execute_parallel("Analyze this",
  providers: [:claude, :gemini]
)

# Cascade with fallback
{:ok, result} = CodingAgent.execute_cascade("Generate tests")
```

## Routing Strategy

Tasks are automatically routed based on type:

| Task Type | Provider | Reason |
|-----------|----------|--------|
| `:generate` | Claude | Careful reasoning for complex generation |
| `:review` | Codex | Tool-calling, quick review |
| `:analyze` | Gemini | Large context window |
| `:explain` | Gemini | Clear explanations |
| `:refactor` | Claude | Careful reasoning, preserves behavior |
| `:fix` | Codex | Tool-calling, file edits |

## Architecture

```
CodingAgent
├── Task         # Task struct with type inference
├── Router       # Hard-wired routing logic
├── Providers/
│   ├── Claude   # claude_agent_sdk adapter
│   ├── Codex    # codex_sdk adapter
│   └── Gemini   # gemini_ex adapter
├── Prompts/
│   ├── Claude   # Chain-of-thought prompts
│   ├── Codex    # Action-oriented prompts
│   └── Gemini   # Context-heavy prompts
├── Actions/
│   ├── ExecuteProvider   # Jido action for provider execution
│   └── AggregateResults  # Jido action for combining results
└── Workflows/
    ├── SingleProvider    # Single provider execution
    ├── ParallelReview    # Multi-provider parallel
    └── Cascade           # Fallback chain
```

## Configuration

### Required API Keys

Set at least one:

```bash
export ANTHROPIC_API_KEY="..."  # For Claude
export OPENAI_API_KEY="..."     # For Codex
export GEMINI_API_KEY="..."     # For Gemini
```

### Check Available Providers

```elixir
iex> CodingAgent.available_providers()
[:claude, :gemini]  # Only those with valid API keys
```

## Testing

```bash
# Unit tests (no API keys needed)
mix test

# Integration tests (requires API keys)
mix test --include integration

# Provider-specific integration
mix test --include claude
mix test --include codex
mix test --include gemini
```

## Example Workflows

### 1. Code Generation

```elixir
{:ok, result} = CodingAgent.execute("""
Write a GenServer that:
1. Maintains a counter
2. Supports increment/decrement
3. Has a configurable limit
""", language: "elixir")

IO.puts(result.content)
```

### 2. Code Review

```elixir
code = File.read!("lib/my_module.ex")

{:ok, result} = CodingAgent.execute(
  "Review this code for security issues and performance",
  type: :review,
  context: code,
  language: "elixir"
)
```

### 3. Multi-Provider Analysis

```elixir
{:ok, result} = CodingAgent.execute_parallel(
  "Analyze the architecture of this module",
  context: File.read!("lib/complex_module.ex")
)

# Get combined insights
IO.puts(result.combined)

# Or individual provider results
IO.inspect(result.individual)
```

## License

MIT - See parent synapse project.
