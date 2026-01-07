defmodule ResearchAgent.Workflows.DeepResearch do
  @moduledoc """
  Deep research workflow with cascade fallback strategy.

  This workflow demonstrates the cascade pattern: uses Gemini for fast
  initial search, then falls back to Claude for high-quality synthesis
  if Gemini is unavailable. Includes an intermediate summarization step
  for better processing of multiple sources.

  ## Workflow Steps

  1. Search - Find sources (Gemini primary, Claude fallback)
  2. Fetch - Process and filter sources by reliability
  3. Summarize - Create concise summaries of each source
  4. Synthesize - Deep synthesis using Claude (Gemini fallback)

  ## Cascade Strategy

  - **Search**: Gemini (fast) → Claude (fallback)
  - **Synthesis**: Claude (quality) → Gemini (fallback)

  ## Example

      query = Query.new("Impact of AI on healthcare", depth: :deep)
      {:ok, result} = DeepResearch.run(query)
  """

  alias ResearchAgent.{Query, Actions, Providers}
  alias Synapse.Workflow.{Spec, Engine}

  @doc """
  Run a deep research workflow with cascade fallback.

  ## Options

    * `:search_provider` - Primary search provider (default: auto-select)
    * `:synthesis_provider` - Primary synthesis provider (default: auto-select)
    * `:request_id` - Optional request ID for tracking
  """
  @spec run(Query.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Query{} = query, opts \\ []) do
    search_provider = select_search_provider(opts)
    synthesis_provider = select_synthesis_provider(opts)
    request_id = Keyword.get(opts, :request_id, query.id)

    spec =
      Spec.new(
        name: :deep_research,
        description: "Deep research with cascade provider fallback",
        steps: [
          [
            id: :search,
            action: Actions.SearchWeb,
            label: "Search for sources",
            description: "Search web using primary provider with cascade fallback",
            params: fn env ->
              %{
                query: env.input.query,
                provider: search_provider
              }
            end,
            retry: %{max_attempts: 2, backoff: 1000},
            on_error: :continue
          ],
          [
            id: :fetch,
            action: Actions.FetchContent,
            label: "Fetch and filter sources",
            description: "Convert search results to sources with reliability scoring",
            requires: [:search],
            params: fn env ->
              %{
                search_results: env.results.search,
                reliability_threshold: env.input.query.reliability_threshold
              }
            end
          ],
          [
            id: :summarize,
            action: Actions.Summarize,
            label: "Summarize sources",
            description: "Create concise summaries for each source",
            requires: [:fetch],
            params: fn env ->
              %{
                sources: env.results.fetch.sources,
                max_summary_length: 1000
              }
            end
          ],
          [
            id: :synthesize,
            action: Actions.Synthesize,
            label: "Synthesize research",
            description: "Create comprehensive research output using synthesis provider",
            requires: [:summarize],
            params: fn env ->
              %{
                sources: env.results.summarize.sources,
                query: env.input.query,
                provider: synthesis_provider
              }
            end,
            retry: %{max_attempts: 2, backoff: 1000}
          ]
        ],
        outputs: [
          Spec.output(:content, from: :synthesize, path: [:content]),
          Spec.output(:provider, from: :synthesize, path: [:provider]),
          Spec.output(:sources, from: :summarize, path: [:sources]),
          Spec.output(:source_count, from: :fetch, path: [:filtered_count]),
          Spec.output(:metadata,
            from: :synthesize,
            transform: fn synthesis_result, env ->
              %{
                search_provider: search_provider,
                synthesis_provider: synthesis_result.provider,
                source_count: env.state.results.fetch.filtered_count,
                total_found: env.state.results.fetch.total_found,
                workflow_type: :deep_research
              }
            end
          )
        ],
        metadata: %{
          workflow_type: :deep_research,
          search_provider: search_provider,
          synthesis_provider: synthesis_provider,
          cascade_enabled: true
        }
      )

    Engine.execute(spec,
      input: %{query: query},
      context: %{request_id: request_id}
    )
  end

  # Private helpers

  defp select_search_provider(opts) do
    case Keyword.get(opts, :search_provider) do
      nil ->
        # Auto-select: prefer Gemini for speed
        cond do
          Providers.Gemini.available?() -> :gemini
          Providers.Claude.available?() -> :claude
          true -> :gemini
        end

      provider ->
        provider
    end
  end

  defp select_synthesis_provider(opts) do
    case Keyword.get(opts, :synthesis_provider) do
      nil ->
        # Auto-select: prefer Claude for quality
        cond do
          Providers.Claude.available?() -> :claude
          Providers.Gemini.available?() -> :gemini
          true -> :claude
        end

      provider ->
        provider
    end
  end
end
