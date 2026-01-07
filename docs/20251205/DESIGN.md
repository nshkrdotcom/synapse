# Multi-Model Coding Agent Design Document

> A functional example app orchestrating claude_agent_sdk, codex_sdk, and gemini_ex via Synapse.

## 1. Architecture Overview

### High-Level Architecture

```
+------------------------------------------------------------+
|                    CodingAgent Application                   |
+------------------------------------------------------------+
|                                                              |
|  +------------------+    +------------------+                |
|  |   CLI / Entry    |    |  Signal Router   | <-- synapse   |
|  +------------------+    +------------------+                |
|           |                      ^                           |
|           v                      |                           |
|  +------------------+    +------------------+                |
|  | Task Dispatcher  | -> | Workflow Engine  | <-- synapse   |
|  +------------------+    +------------------+                |
|           |                      |                           |
|           v                      v                           |
|  +------------------+  +------------------+                  |
|  |  Task Router     |  |  Persistence     | <-- synapse     |
|  +------------------+  +------------------+                  |
|           |                                                  |
|     +-----+-----+-----+                                      |
|     |           |     |                                      |
|     v           v     v                                      |
|  +------+  +------+  +--------+                              |
|  |Claude|  |Codex |  |Gemini  |                              |
|  |Agent |  |Agent |  |Agent   |                              |
|  +------+  +------+  +--------+                              |
|     |           |          |                                 |
|     v           v          v                                 |
|  +------+  +------+  +--------+                              |
|  |claude|  |codex |  |gemini  |                              |
|  |_sdk  |  |_sdk  |  |_ex     |                              |
|  +------+  +------+  +--------+                              |
+------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **Synapse Workflow Engine** | DAG execution, persistence, audit trails |
| **Synapse Signal Router** | Event-driven communication between components |
| **Task Router** | Hard-wired routing logic - routes tasks to providers based on task type |
| **Provider Adapters** | Thin wrappers around each SDK providing uniform interface |
| **Workflow Steps** | Jido Actions that execute provider-specific operations |

---

## 2. Directory Structure

```
synapse/examples/coding_agent/
├── mix.exs                           # Mix project definition
├── config/
│   ├── config.exs                    # Base configuration
│   ├── dev.exs                       # Development config (API keys)
│   ├── test.exs                      # Test configuration
│   └── runtime.exs                   # Runtime config with env vars
├── lib/
│   ├── coding_agent.ex               # Main entry module
│   ├── coding_agent/
│   │   ├── application.ex            # OTP Application
│   │   ├── cli.ex                    # Command-line interface
│   │   │
│   │   ├── router.ex                 # Task routing logic
│   │   ├── task.ex                   # Task struct definition
│   │   │
│   │   ├── providers/
│   │   │   ├── behaviour.ex          # Provider behaviour
│   │   │   ├── claude.ex             # Claude adapter
│   │   │   ├── codex.ex              # Codex adapter
│   │   │   └── gemini.ex             # Gemini adapter
│   │   │
│   │   ├── actions/
│   │   │   ├── execute_provider.ex   # Generic provider execution action
│   │   │   ├── aggregate_results.ex  # Multi-provider result aggregation
│   │   │   └── format_output.ex      # Output formatting action
│   │   │
│   │   ├── workflows/
│   │   │   ├── single_provider.ex    # Simple single-provider workflow
│   │   │   ├── parallel_review.ex    # Multi-provider parallel review
│   │   │   └── cascade.ex            # Cascade workflow (fallback chain)
│   │   │
│   │   ├── prompts/
│   │   │   ├── templates.ex          # Prompt template module
│   │   │   ├── claude.ex             # Claude-specific prompts
│   │   │   ├── codex.ex              # Codex-specific prompts
│   │   │   └── gemini.ex             # Gemini-specific prompts
│   │   │
│   │   ├── signals.ex                # Signal definitions
│   │   └── telemetry.ex              # Telemetry handlers
│   │
│   └── mix/
│       └── tasks/
│           └── coding_agent.ex       # Mix task for CLI
│
└── test/
    ├── test_helper.exs
    ├── coding_agent_test.exs
    ├── providers/
    │   ├── claude_test.exs
    │   ├── codex_test.exs
    │   └── gemini_test.exs
    ├── workflows/
    │   └── single_provider_test.exs
    └── support/
        ├── fixtures.ex
        └── mocks.ex
```

---

## 3. Core Modules

### 3.1 Entry Point (`lib/coding_agent.ex`)

```elixir
defmodule CodingAgent do
  @moduledoc """
  Multi-model coding agent orchestrating Claude, Codex, and Gemini.
  """

  alias CodingAgent.{Router, Task, Workflows}

  @doc "Execute a coding task with automatic provider selection."
  @spec execute(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(input, opts \\ []) do
    task = Task.new(input, opts)
    provider = opts[:provider] || Router.route(task)
    Workflows.SingleProvider.run(task, provider)
  end

  @doc "Execute with all providers in parallel."
  @spec execute_parallel(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_parallel(input, opts \\ []) do
    task = Task.new(input, opts)
    providers = Keyword.get(opts, :providers, [:claude, :codex, :gemini])
    Workflows.ParallelReview.run(task, providers)
  end

  @doc "Execute with fallback chain."
  @spec execute_cascade(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_cascade(input, opts \\ []) do
    task = Task.new(input, opts)
    Workflows.Cascade.run(task, [:claude, :codex, :gemini])
  end
end
```

### 3.2 Task Struct (`lib/coding_agent/task.ex`)

```elixir
defmodule CodingAgent.Task do
  @moduledoc "Represents a coding task with input, type, and metadata."

  @enforce_keys [:id, :input, :type]
  defstruct [
    :id,
    :input,
    :type,           # :generate | :review | :analyze | :refactor | :explain | :fix
    :context,        # Optional code context
    :language,       # Programming language hint
    :files,          # File paths if applicable
    :metadata,
    inserted_at: nil
  ]

  @type task_type :: :generate | :review | :analyze | :refactor | :explain | :fix

  @spec new(String.t(), keyword()) :: t()
  def new(input, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      input: input,
      type: opts[:type] || infer_type(input),
      context: opts[:context],
      language: opts[:language],
      files: opts[:files],
      metadata: opts[:metadata] || %{},
      inserted_at: DateTime.utc_now()
    }
  end

  defp generate_id, do: "task_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

  defp infer_type(input) do
    input_lower = String.downcase(input)
    cond do
      String.contains?(input_lower, ["generate", "create", "write", "build"]) -> :generate
      String.contains?(input_lower, ["review", "check", "audit"]) -> :review
      String.contains?(input_lower, ["analyze", "explain", "understand"]) -> :analyze
      String.contains?(input_lower, ["refactor", "improve", "optimize"]) -> :refactor
      String.contains?(input_lower, ["fix", "bug", "error", "issue"]) -> :fix
      true -> :generate
    end
  end
end
```

### 3.3 Router (`lib/coding_agent/router.ex`)

```elixir
defmodule CodingAgent.Router do
  @moduledoc """
  Hard-wired routing logic for task-to-provider mapping.

  Strategy:
  - generate/refactor: Claude (careful reasoning)
  - review/fix: Codex (tool-calling, file edits)
  - analyze/explain: Gemini (large context window)
  """

  alias CodingAgent.Task

  @routing_table %{
    generate: :claude,
    review: :codex,
    analyze: :gemini,
    explain: :gemini,
    refactor: :claude,
    fix: :codex
  }

  @spec route(Task.t()) :: atom()
  def route(%Task{type: type}), do: Map.get(@routing_table, type, :claude)

  @spec available_providers() :: [atom()]
  def available_providers, do: [:claude, :codex, :gemini]
end
```

### 3.4 Provider Behaviour (`lib/coding_agent/providers/behaviour.ex`)

```elixir
defmodule CodingAgent.Providers.Behaviour do
  @moduledoc "Behaviour for provider adapters."

  alias CodingAgent.Task

  @type result :: %{
    content: String.t(),
    provider: atom(),
    model: String.t() | nil,
    usage: map() | nil,
    raw: term()
  }

  @callback execute(Task.t(), keyword()) :: {:ok, result()} | {:error, term()}
  @callback available?() :: boolean()
  @callback name() :: atom()
end
```

---

## 4. Provider Implementations

### 4.1 Claude Provider

```elixir
defmodule CodingAgent.Providers.Claude do
  @behaviour CodingAgent.Providers.Behaviour

  alias CodingAgent.{Task, Prompts}

  @impl true
  def name, do: :claude

  @impl true
  def available?, do: System.get_env("ANTHROPIC_API_KEY") != nil

  @impl true
  def execute(%Task{} = task, opts \\ []) do
    options = %ClaudeAgentSDK.Options{
      system_prompt: Prompts.Claude.system_prompt_for(task.type),
      max_turns: Keyword.get(opts, :max_turns, 3)
    }

    prompt = Prompts.Claude.format_task(task)
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    case extract_result(messages) do
      {:ok, content} ->
        {:ok, %{
          content: content,
          provider: :claude,
          model: extract_model(messages),
          usage: extract_usage(messages),
          raw: messages
        }}
      {:error, reason} ->
        {:error, {:claude_error, reason}}
    end
  end

  defp extract_result(messages) do
    text = messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ClaudeAgentSDK.ContentExtractor.extract_text/1)
    |> Enum.join("\n")

    if text == "", do: {:error, :no_response}, else: {:ok, text}
  end

  defp extract_model(messages) do
    Enum.find_value(messages, fn m -> m[:model] end)
  end

  defp extract_usage(messages) do
    Enum.find_value(messages, fn m -> m[:usage] end) || %{}
  end
end
```

### 4.2 Codex Provider

```elixir
defmodule CodingAgent.Providers.Codex do
  @behaviour CodingAgent.Providers.Behaviour

  alias CodingAgent.{Task, Prompts}

  @impl true
  def name, do: :codex

  @impl true
  def available?, do: System.get_env("OPENAI_API_KEY") != nil

  @impl true
  def execute(%Task{} = task, opts \\ []) do
    codex_opts = %{
      model: Keyword.get(opts, :model, "o4-mini"),
      instructions: Prompts.Codex.system_prompt_for(task.type)
    }

    prompt = Prompts.Codex.format_task(task)

    with {:ok, thread} <- Codex.start_thread(codex_opts),
         {:ok, result} <- Codex.Thread.run(thread, prompt) do
      {:ok, %{
        content: result.final_response.text || "",
        provider: :codex,
        model: codex_opts.model,
        usage: result.usage,
        raw: result
      }}
    else
      {:error, reason} -> {:error, {:codex_error, reason}}
    end
  end
end
```

### 4.3 Gemini Provider

```elixir
defmodule CodingAgent.Providers.Gemini do
  @behaviour CodingAgent.Providers.Behaviour

  alias CodingAgent.{Task, Prompts}

  @impl true
  def name, do: :gemini

  @impl true
  def available?, do: System.get_env("GEMINI_API_KEY") != nil

  @impl true
  def execute(%Task{} = task, opts \\ []) do
    gemini_opts = [
      model: Keyword.get(opts, :model, "gemini-2.0-flash-exp"),
      system_instruction: Prompts.Gemini.system_prompt_for(task.type),
      temperature: Keyword.get(opts, :temperature, 0.3)
    ]

    prompt = Prompts.Gemini.format_task(task)

    case Gemini.text(prompt, gemini_opts) do
      {:ok, text} ->
        {:ok, %{
          content: text,
          provider: :gemini,
          model: gemini_opts[:model],
          usage: nil,
          raw: text
        }}
      {:error, error} ->
        {:error, {:gemini_error, error}}
    end
  end
end
```

---

## 5. Workflows

### 5.1 Single Provider Workflow

```elixir
defmodule CodingAgent.Workflows.SingleProvider do
  @moduledoc "Execute task with a single provider via Synapse workflow engine."

  alias Synapse.Workflow.{Spec, Engine}
  alias CodingAgent.Actions.ExecuteProvider

  def run(task, provider) do
    spec = Spec.new(
      name: :single_provider_coding,
      description: "Execute coding task with #{provider}",
      metadata: %{task_id: task.id, provider: provider},
      steps: [
        [
          id: :execute,
          action: ExecuteProvider,
          params: %{task: task, provider: provider},
          retry: [max_attempts: 3, backoff: 1000]
        ]
      ],
      outputs: [
        [key: :result, from: :execute]
      ]
    )

    Engine.execute(spec,
      input: %{task: task, provider: provider},
      context: %{request_id: task.id}
    )
  end
end
```

### 5.2 Parallel Review Workflow

```elixir
defmodule CodingAgent.Workflows.ParallelReview do
  @moduledoc "Run task through multiple providers and aggregate results."

  alias Synapse.Workflow.{Spec, Engine}
  alias CodingAgent.Actions.{ExecuteProvider, AggregateResults}

  def run(task, providers) do
    provider_steps = Enum.map(providers, fn provider ->
      [
        id: :"#{provider}_execute",
        action: ExecuteProvider,
        params: %{task: task, provider: provider},
        on_error: :continue,
        retry: [max_attempts: 2, backoff: 500]
      ]
    end)

    aggregate_step = [
      id: :aggregate,
      action: AggregateResults,
      requires: Enum.map(providers, &:"#{&1}_execute"),
      params: fn env ->
        results = Enum.map(providers, fn provider ->
          {provider, Map.get(env.results, :"#{provider}_execute")}
        end)
        %{results: results, task: task}
      end
    ]

    spec = Spec.new(
      name: :parallel_review,
      description: "Execute task with #{length(providers)} providers",
      metadata: %{task_id: task.id, providers: providers},
      steps: provider_steps ++ [aggregate_step],
      outputs: [
        [key: :combined, from: :aggregate],
        [key: :individual, from: :aggregate, path: [:individual]]
      ]
    )

    Engine.execute(spec,
      input: %{task: task, providers: providers},
      context: %{request_id: task.id}
    )
  end
end
```

### 5.3 Cascade Workflow

```elixir
defmodule CodingAgent.Workflows.Cascade do
  @moduledoc "Try providers in order, falling back on failure."

  alias CodingAgent.Providers

  def run(task, providers) do
    Enum.reduce_while(providers, {:error, :all_failed}, fn provider, _acc ->
      module = resolve_provider(provider)

      if module.available?() do
        case module.execute(task) do
          {:ok, result} ->
            {:halt, {:ok, Map.put(result, :cascade_position, provider)}}
          {:error, _} ->
            {:cont, {:error, :all_failed}}
        end
      else
        {:cont, {:error, :all_failed}}
      end
    end)
  end

  defp resolve_provider(:claude), do: Providers.Claude
  defp resolve_provider(:codex), do: Providers.Codex
  defp resolve_provider(:gemini), do: Providers.Gemini
end
```

---

## 6. Prompting Strategy

### 6.1 Claude Prompts (Reasoning-Heavy)

```elixir
defmodule CodingAgent.Prompts.Claude do
  @system_prompts %{
    generate: """
    You are an expert software engineer. When generating code:
    1. Think through the requirements step by step
    2. Consider edge cases and error handling
    3. Write clean, well-documented code
    4. Explain your design decisions briefly
    """,
    review: """
    You are a senior code reviewer. For each piece of code:
    1. Identify potential bugs and issues
    2. Suggest improvements for readability
    3. Check for security vulnerabilities
    4. Rate the code quality (1-10)
    """,
    refactor: """
    You are a refactoring specialist. When refactoring:
    1. Preserve existing behavior exactly
    2. Improve code structure and clarity
    3. Apply SOLID principles where appropriate
    4. Explain each change you make
    """
  }

  def system_prompt_for(type), do: Map.get(@system_prompts, type, @system_prompts[:generate])

  def format_task(task) do
    base = "## Task\n\n#{task.input}"
    context = if task.context, do: "\n\n## Context\n\n```#{task.language || ""}\n#{task.context}\n```", else: ""
    base <> context
  end
end
```

### 6.2 Codex Prompts (Action-Oriented)

```elixir
defmodule CodingAgent.Prompts.Codex do
  @system_prompts %{
    generate: """
    Generate clean, idiomatic code. Follow existing codebase patterns.
    Include inline comments for complex logic. Output code only.
    """,
    review: """
    Review the code for bugs, security issues, and improvements.
    Be specific and actionable. List issues as bullet points.
    """,
    fix: """
    Fix the reported issue. Show the corrected code.
    Explain what was wrong and how you fixed it.
    """
  }

  def system_prompt_for(type), do: Map.get(@system_prompts, type, @system_prompts[:generate])

  def format_task(task) do
    parts = [task.input]
    if task.context, do: parts ++ ["Code:\n```\n#{task.context}\n```"], else: parts
    Enum.join(parts, "\n\n")
  end
end
```

### 6.3 Gemini Prompts (Context-Heavy)

```elixir
defmodule CodingAgent.Prompts.Gemini do
  @system_prompts %{
    analyze: """
    Analyze the provided code thoroughly. Consider:
    - Overall architecture and design patterns
    - Performance characteristics
    - Potential issues and risks
    - Suggestions for improvement
    Format your response in clear sections.
    """,
    explain: """
    Explain the code in detail. Cover:
    - What the code does at a high level
    - How each major component works
    - Any non-obvious logic or patterns
    Use examples where helpful.
    """,
    generate: """
    Generate efficient, well-structured code.
    Focus on performance and clarity.
    Include brief comments explaining key decisions.
    """
  }

  def system_prompt_for(type), do: Map.get(@system_prompts, type, @system_prompts[:generate])

  def format_task(task) do
    sections = ["## Task\n#{task.input}"]
    sections = if task.context, do: sections ++ ["## Code\n```\n#{task.context}\n```"], else: sections
    sections = if task.files, do: sections ++ ["## Files\n#{Enum.join(task.files, "\n")}"], else: sections
    Enum.join(sections, "\n\n")
  end
end
```

---

## 7. Actions (Jido-Compatible)

### 7.1 ExecuteProvider Action

```elixir
defmodule CodingAgent.Actions.ExecuteProvider do
  use Jido.Action,
    name: "execute_provider",
    description: "Execute a coding task with a specific provider",
    schema: [
      task: [type: :map, required: true],
      provider: [type: :atom, required: true]
    ]

  alias CodingAgent.Providers

  @impl true
  def run(params, _context) do
    task = struct(CodingAgent.Task, params.task)
    provider = params.provider
    module = resolve_provider(provider)

    if module.available?() do
      module.execute(task)
    else
      {:error, {:provider_unavailable, provider}}
    end
  end

  defp resolve_provider(:claude), do: Providers.Claude
  defp resolve_provider(:codex), do: Providers.Codex
  defp resolve_provider(:gemini), do: Providers.Gemini
end
```

### 7.2 AggregateResults Action

```elixir
defmodule CodingAgent.Actions.AggregateResults do
  use Jido.Action,
    name: "aggregate_results",
    description: "Aggregate results from multiple providers",
    schema: [
      results: [type: {:list, :any}, required: true],
      task: [type: :map, required: true]
    ]

  @impl true
  def run(params, _context) do
    results = params.results

    successful = Enum.filter(results, fn {_provider, result} ->
      match?({:ok, _}, result) || (is_map(result) && result[:content])
    end)

    combined_content = successful
    |> Enum.map(fn {provider, result} ->
      content = if is_map(result), do: result.content, else: elem(result, 1).content
      "## #{provider}\n\n#{content}"
    end)
    |> Enum.join("\n\n---\n\n")

    {:ok, %{
      combined: combined_content,
      individual: results,
      success_count: length(successful),
      total_count: length(results)
    }}
  end
end
```

---

## 8. CLI Interface

```elixir
defmodule Mix.Tasks.CodingAgent do
  use Mix.Task

  @shortdoc "Run a coding task through the multi-model agent"

  @moduledoc """
  Run a coding task through the multi-model agent.

  ## Usage

      mix coding_agent "Write a function to parse JSON"
      mix coding_agent "Review this code" --type review --provider codex
      mix coding_agent "Explain this algorithm" --parallel

  ## Options

    * `--type` - Task type: generate, review, analyze, refactor, explain, fix
    * `--provider` - Specific provider: claude, codex, gemini
    * `--parallel` - Run with all providers
    * `--cascade` - Try providers in sequence until one succeeds
    * `--context` - Code context to include
    * `--language` - Programming language hint
  """

  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} = OptionParser.parse(args,
      switches: [
        type: :string,
        provider: :string,
        parallel: :boolean,
        cascade: :boolean,
        context: :string,
        language: :string
      ]
    )

    input = Enum.join(args, " ")

    if input == "" do
      Mix.raise("Please provide a task description")
    end

    task_opts = [
      type: opts[:type] && String.to_atom(opts[:type]),
      context: opts[:context],
      language: opts[:language]
    ] |> Enum.reject(fn {_, v} -> is_nil(v) end)

    result = cond do
      opts[:parallel] ->
        CodingAgent.execute_parallel(input, task_opts)
      opts[:cascade] ->
        CodingAgent.execute_cascade(input, task_opts)
      opts[:provider] ->
        CodingAgent.execute(input, [{:provider, String.to_atom(opts[:provider])} | task_opts])
      true ->
        CodingAgent.execute(input, task_opts)
    end

    case result do
      {:ok, %{outputs: %{result: result}}} ->
        IO.puts("\n#{result.content}")
      {:ok, %{outputs: %{combined: combined}}} ->
        IO.puts("\n#{combined}")
      {:ok, result} when is_map(result) ->
        IO.puts("\n#{result.content}")
      {:error, reason} ->
        Mix.raise("Task failed: #{inspect(reason)}")
    end
  end
end
```

---

## 9. Configuration

### mix.exs

```elixir
defmodule CodingAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :coding_agent,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {CodingAgent.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Parent framework
      {:synapse, path: "../.."},

      # SDK dependencies
      {:claude_agent_sdk, "~> 0.6"},
      {:codex_sdk, "~> 0.2"},
      {:gemini_ex, "~> 0.7"},

      # Testing
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
```

### config/config.exs

```elixir
import Config

config :coding_agent,
  default_provider: :claude

config :synapse, Synapse.Workflow.Engine,
  persistence: {Synapse.Workflow.Persistence.Postgres, []}

import_config "#{config_env()}.exs"
```

### config/runtime.exs

```elixir
import Config

# Check provider availability from environment
config :coding_agent,
  claude_available: System.get_env("ANTHROPIC_API_KEY") != nil,
  codex_available: System.get_env("OPENAI_API_KEY") != nil,
  gemini_available: System.get_env("GEMINI_API_KEY") != nil

if api_key = System.get_env("GEMINI_API_KEY") do
  config :gemini_ex, api_key: api_key
end
```

---

## 10. Testing Strategy

### Unit Tests (Mocked Providers)

```elixir
# test/providers/claude_test.exs
defmodule CodingAgent.Providers.ClaudeTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "executes task and returns formatted result" do
    task = CodingAgent.Task.new("Write hello world", type: :generate)

    expect(ClaudeAgentSDK.Mock, :query, fn _prompt, _opts ->
      [%{type: :assistant, content: "Here is the code: puts 'hello'"}]
    end)

    assert {:ok, result} = CodingAgent.Providers.Claude.execute(task)
    assert result.provider == :claude
    assert result.content =~ "hello"
  end
end
```

### Integration Tests

```elixir
# test/workflows/single_provider_test.exs
defmodule CodingAgent.Workflows.SingleProviderTest do
  use ExUnit.Case

  @tag :integration
  test "executes task through workflow engine" do
    task = CodingAgent.Task.new("Generate a hello world", type: :generate)

    assert {:ok, result} = CodingAgent.Workflows.SingleProvider.run(task, :gemini)
    assert result.outputs.result.content != ""
  end
end
```

---

## 11. Example Usage

```bash
# Setup
cd synapse/examples/coding_agent
mix deps.get

# Set API keys
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="..."

# Simple usage
mix coding_agent "Write a function to calculate fibonacci numbers in Elixir"

# Specific provider
mix coding_agent "Review this code for security issues" --provider codex

# Parallel execution
mix coding_agent "Analyze the time complexity of this algorithm" --parallel

# With context
mix coding_agent "Refactor this function" --context "def foo(x), do: x + 1" --language elixir

# IEx usage
iex -S mix
iex> CodingAgent.execute("Write a GenServer for caching")
iex> CodingAgent.execute_parallel("Review this code", context: "...")
```

---

## 12. Future Enhancements

1. **Streaming Output** - Stream responses as they arrive from providers
2. **Cost Tracking** - Track and report API costs per execution
3. **Result Caching** - Cache results for identical tasks
4. **Provider Health Checks** - Monitor provider availability
5. **Custom Routing Rules** - Allow user-defined routing logic
6. **Tool Integration** - Let Codex/Claude use file system tools
7. **Conversation Mode** - Multi-turn interactions
