# DocGenerator

A multi-provider documentation generator for Elixir projects, built on the Synapse workflow orchestration framework.

DocGenerator demonstrates how to use Synapse to orchestrate multiple AI providers (Claude, Codex, and Gemini) in parallel to analyze Elixir codebases and generate comprehensive documentation.

## Features

- **Parallel Workflow Execution**: Generate documentation using multiple AI providers simultaneously
- **Code Analysis**: Automatic extraction of functions, types, specs, and callbacks via Elixir introspection
- **Multi-format Output**: Generate module docs, README files, and usage guides
- **Style Customization**: Choose from formal, casual, tutorial, or reference documentation styles
- **Provider Specialization**:
  - **Claude**: Technical accuracy and comprehensive explanations
  - **Codex**: Practical code examples and usage patterns
  - **Gemini**: Clear, accessible explanations for broader audiences

## Installation

This is an example application demonstrating Synapse workflows. To use it:

```bash
cd examples/doc_generator
mix deps.get
```

## Configuration

Set up API keys for the providers you want to use:

```bash
export ANTHROPIC_API_KEY=your_claude_key
export OPENAI_API_KEY=your_openai_key
export GEMINI_API_KEY=your_gemini_key
```

## Usage

### Basic Usage

```elixir
# Generate documentation for a single module using Claude
{:ok, result} = DocGenerator.generate(MyApp.User)

# Use a specific provider
{:ok, result} = DocGenerator.generate(MyApp.User, provider: :codex)

# Choose a documentation style
{:ok, result} = DocGenerator.generate(MyApp.User,
  provider: :gemini,
  style: :tutorial
)
```

### Parallel Documentation Generation

Generate documentation using multiple providers simultaneously:

```elixir
# Use all providers in parallel
{:ok, result} = DocGenerator.generate_parallel(MyApp.User)

# Use specific providers
{:ok, result} = DocGenerator.generate_parallel(MyApp.User,
  providers: [:claude, :gemini]
)

# Access individual provider results
result[:individual][:claude]
result[:individual][:codex]
result[:individual][:gemini]

# Get merged documentation
result[:merged]
```

### Project Documentation

Generate documentation for an entire project:

```elixir
# Document all modules in a project
{:ok, result} = DocGenerator.generate_project("/path/to/project")

# Document specific modules
{:ok, result} = DocGenerator.generate_project(".",
  modules: [MyApp.User, MyApp.Post, MyApp.Comment],
  providers: [:claude, :codex, :gemini],
  style: :formal
)
```

### Check Provider Availability

```elixir
# List all available providers
DocGenerator.available_providers()
# => [:claude, :codex]

# Check specific provider
DocGenerator.provider_available?(:claude)
# => true
```

## Documentation Styles

### Formal (Default)

Professional, technical documentation with precise terminology:

```elixir
DocGenerator.generate(MyModule, style: :formal)
```

### Casual

Approachable, friendly documentation in plain language:

```elixir
DocGenerator.generate(MyModule, style: :casual)
```

### Tutorial

Step-by-step, learning-focused documentation:

```elixir
DocGenerator.generate(MyModule, style: :tutorial)
```

### Reference

Concise API reference focused on parameters and return values:

```elixir
DocGenerator.generate(MyModule, style: :reference)
```

## Architecture

DocGenerator is built on Synapse's workflow engine and demonstrates several key patterns:

### Parallel Execution Pattern

Like the `ParallelReview` workflow in the coding_agent example, DocGenerator executes multiple provider steps in parallel:

```elixir
# Each provider runs independently
provider_steps = for provider <- [:claude, :codex, :gemini] do
  [
    id: :"#{provider}_generate",
    action: GenerateModuleDoc,
    params: %{module: module, provider: provider},
    on_error: :continue
  ]
end

# Results are aggregated
[
  id: :aggregate,
  action: AggregateDocs,
  requires: [:claude_generate, :codex_generate, :gemini_generate]
]
```

### Code Analysis

Uses Elixir's introspection capabilities:

```elixir
# Extract module metadata
{:docs_v1, _, _, _, moduledoc, _, docs} = Code.fetch_docs(module)
functions = module.__info__(:functions)
{:ok, types} = Code.Typespec.fetch_types(module)
{:ok, callbacks} = Code.Typespec.fetch_callbacks(module)
```

### Provider Abstraction

All providers implement a common behaviour:

```elixir
@callback generate_module_doc(ModuleInfo.t(), generation_opts()) ::
  {:ok, result()} | {:error, term()}
```

## Example Output

For a module like:

```elixir
defmodule MyApp.User do
  @type t :: %{name: String.t(), email: String.t()}

  def create(name, email), do: %{name: name, email: email}
  def get_name(%{name: name}), do: name
end
```

DocGenerator produces:

```markdown
# MyApp.User

User management module for handling user data structures and operations.

## Overview

This module provides functionality for creating and manipulating user records...

## Types

- `@type t` - User struct with name and email fields

## Functions

- `create/2` - Creates a new user with the given name and email
- `get_name/1` - Extracts the name from a user struct

## Examples

    iex> user = MyApp.User.create("Alice", "alice@example.com")
    %{name: "Alice", email: "alice@example.com"}

    iex> MyApp.User.get_name(user)
    "Alice"
```

## Running Tests

```bash
mix test
```

Note: Tests that require API credentials are skipped by default. Set the appropriate environment variables to run integration tests.

## Project Structure

```
doc_generator/
├── lib/
│   ├── doc_generator.ex              # Main API
│   ├── doc_generator/
│   │   ├── application.ex
│   │   ├── project.ex                # Project representation
│   │   ├── module_info.ex            # Module metadata
│   │   ├── analyzer.ex               # Code introspection
│   │   ├── providers/                # AI provider adapters
│   │   │   ├── behaviour.ex
│   │   │   ├── claude.ex
│   │   │   ├── codex.ex
│   │   │   └── gemini.ex
│   │   ├── actions/                  # Jido actions
│   │   │   ├── analyze_module.ex
│   │   │   ├── generate_module_doc.ex
│   │   │   ├── aggregate_docs.ex
│   │   │   └── ...
│   │   ├── workflows/                # Synapse workflows
│   │   │   ├── single_module.ex
│   │   │   └── full_project.ex
│   │   └── outputs/                  # Output formatters
│   │       ├── markdown.ex
│   │       └── exdoc.ex
└── test/
    ├── support/fixtures.ex
    └── doc_generator/
```

## Key Design Decisions

See [DESIGN.md](DESIGN.md) for detailed architecture decisions and patterns.

## License

This example is part of the Synapse framework and follows the same license.
