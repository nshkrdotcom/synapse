defmodule ResearchAgent.Workflows.QuickResearch do
  @moduledoc """
  Quick research workflow using a single provider.

  This workflow provides fast research results using Gemini for both
  search and synthesis. Ideal for simple queries that don't require
  deep analysis or multiple sources.

  ## Workflow Steps

  1. Search - Find relevant sources using Gemini
  2. Fetch - Process search results into Source structs
  3. Synthesize - Create final output using Gemini

  ## Example

      query = Query.new("What is machine learning?")
      {:ok, result} = QuickResearch.run(query)
  """

  alias ResearchAgent.{Query, Actions}
  alias Synapse.Workflow.{Spec, Engine}

  @doc """
  Run a quick research workflow.

  ## Options

    * `:provider` - Provider to use (default: `:gemini`)
    * `:request_id` - Optional request ID for tracking
  """
  @spec run(Query.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Query{} = query, opts \\ []) do
    provider = Keyword.get(opts, :provider, :gemini)
    request_id = Keyword.get(opts, :request_id, query.id)

    spec =
      Spec.new(
        name: :quick_research,
        description: "Fast research using single provider",
        steps: [
          [
            id: :search,
            action: Actions.SearchWeb,
            label: "Search for sources",
            description: "Search web for relevant sources",
            params: fn env ->
              %{
                query: env.input.query,
                provider: provider
              }
            end
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
            id: :synthesize,
            action: Actions.Synthesize,
            label: "Synthesize research",
            description: "Create final research output",
            requires: [:fetch],
            params: fn env ->
              %{
                sources: env.results.fetch.sources,
                query: env.input.query,
                provider: provider
              }
            end
          ]
        ],
        outputs: [
          Spec.output(:content, from: :synthesize, path: [:content]),
          Spec.output(:provider, from: :synthesize, path: [:provider]),
          Spec.output(:sources, from: :fetch, path: [:sources]),
          Spec.output(:source_count, from: :fetch, path: [:filtered_count])
        ],
        metadata: %{
          workflow_type: :quick_research,
          provider: provider
        }
      )

    Engine.execute(spec,
      input: %{query: query},
      context: %{request_id: request_id}
    )
  end
end
