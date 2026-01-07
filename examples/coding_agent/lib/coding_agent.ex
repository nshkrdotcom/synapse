defmodule CodingAgent do
  @moduledoc """
  Multi-model coding agent orchestrating Claude, Codex, and Gemini.

  This is an example application demonstrating how to use synapse's workflow
  engine to orchestrate multiple AI providers for coding tasks.

  ## Usage

      # Simple execution with auto-routing
      {:ok, result} = CodingAgent.execute("Write a function to parse JSON")

      # Specific provider
      {:ok, result} = CodingAgent.execute("Review this code", provider: :codex)

      # Parallel execution with all providers
      {:ok, result} = CodingAgent.execute_parallel("Analyze this algorithm")

      # Cascade (fallback chain)
      {:ok, result} = CodingAgent.execute_cascade("Fix this bug")
  """

  alias CodingAgent.{Router, Task, Workflows}

  @doc """
  Execute a coding task with automatic provider selection.

  ## Options

    * `:type` - Task type: `:generate`, `:review`, `:analyze`, `:refactor`, `:explain`, `:fix`
    * `:provider` - Override automatic routing with specific provider
    * `:context` - Code context to include
    * `:language` - Programming language hint
    * `:files` - List of relevant file paths
    * `:metadata` - Additional metadata map

  ## Examples

      CodingAgent.execute("Write a GenServer for caching")
      CodingAgent.execute("Explain this regex", type: :explain, provider: :gemini)
  """
  @spec execute(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(input, opts \\ []) do
    task = Task.new(input, opts)
    provider = opts[:provider] || Router.route(task)
    Workflows.SingleProvider.run(task, provider)
  end

  @doc """
  Execute a task using multiple providers in parallel and aggregate results.

  ## Options

    * `:providers` - List of providers to use (default: `[:claude, :codex, :gemini]`)
    * All options from `execute/2`

  ## Examples

      CodingAgent.execute_parallel("Review this code for issues")
      CodingAgent.execute_parallel("Analyze", providers: [:claude, :gemini])
  """
  @spec execute_parallel(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_parallel(input, opts \\ []) do
    task = Task.new(input, opts)
    providers = Keyword.get(opts, :providers, [:claude, :codex, :gemini])
    Workflows.ParallelReview.run(task, providers)
  end

  @doc """
  Execute with fallback chain - tries providers in order until one succeeds.

  ## Examples

      CodingAgent.execute_cascade("Generate unit tests")
  """
  @spec execute_cascade(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_cascade(input, opts \\ []) do
    task = Task.new(input, opts)
    providers = Keyword.get(opts, :providers, [:claude, :codex, :gemini])
    Workflows.Cascade.run(task, providers)
  end

  @doc """
  Check which providers are available based on environment configuration.
  """
  @spec available_providers() :: [atom()]
  def available_providers do
    [:claude, :codex, :gemini]
    |> Enum.filter(&provider_available?/1)
  end

  @doc """
  Check if a specific provider is available.
  """
  @spec provider_available?(atom()) :: boolean()
  def provider_available?(provider) do
    case provider do
      :claude -> Application.get_env(:coding_agent, :claude_available, false)
      :codex -> Application.get_env(:coding_agent, :codex_available, false)
      :gemini -> Application.get_env(:coding_agent, :gemini_available, false)
      _ -> false
    end
  end
end
