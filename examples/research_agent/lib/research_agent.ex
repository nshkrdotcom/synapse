defmodule ResearchAgent do
  @moduledoc """
  Multi-provider research agent orchestrating web search, content gathering, and synthesis.

  This is an example application demonstrating how to use Synapse's workflow
  engine to orchestrate research tasks across multiple AI providers with
  cascade fallback strategies.

  ## Features

  - **Cascade Workflows**: Fast initial queries with Gemini, deep synthesis with Claude
  - **Web Search Integration**: Search capabilities via tool definitions
  - **Multi-step Research**: Query → Gather → Synthesize → Present
  - **Source Tracking**: Automatic citation and source reliability scoring

  ## Usage

      # Quick research with auto-routing
      {:ok, result} = ResearchAgent.research("What is quantum computing?")

      # Deep research with multiple steps
      {:ok, result} = ResearchAgent.research("Climate change impacts", depth: :deep)

      # Custom sources and depth
      {:ok, result} = ResearchAgent.research(
        "Machine learning trends 2024",
        depth: :comprehensive,
        max_sources: 15
      )
  """

  alias ResearchAgent.{Query, Workflows}

  @type depth :: :quick | :deep | :comprehensive

  @doc """
  Conduct research on a topic with automatic workflow selection.

  ## Options

    * `:depth` - Research depth: `:quick`, `:deep`, or `:comprehensive` (default: `:quick`)
    * `:max_sources` - Maximum number of sources to gather (default: 10)
    * `:reliability_threshold` - Minimum reliability score for sources (default: 0.6)
    * `:include_citations` - Include detailed citations in output (default: true)
    * `:provider` - Override provider selection (`:gemini` or `:claude`)

  ## Examples

      ResearchAgent.research("What is photosynthesis?")
      ResearchAgent.research("AI ethics", depth: :deep, max_sources: 20)
      ResearchAgent.research("Blockchain technology", provider: :claude)
  """
  @spec research(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def research(topic, opts \\ []) when is_binary(topic) do
    depth = Keyword.get(opts, :depth, :quick)
    query = Query.new(topic, opts)

    case depth do
      :quick ->
        Workflows.QuickResearch.run(query, opts)

      depth when depth in [:deep, :comprehensive] ->
        Workflows.DeepResearch.run(query, opts)

      _ ->
        {:error, {:invalid_depth, depth}}
    end
  end

  @doc """
  Check which providers are available based on environment configuration.
  """
  @spec available_providers() :: [atom()]
  def available_providers do
    [:gemini, :claude]
    |> Enum.filter(&provider_available?/1)
  end

  @doc """
  Check if a specific provider is available.
  """
  @spec provider_available?(atom()) :: boolean()
  def provider_available?(provider) do
    case provider do
      :gemini -> Application.get_env(:research_agent, :gemini_available, false)
      :claude -> Application.get_env(:research_agent, :claude_available, false)
      _ -> false
    end
  end
end
