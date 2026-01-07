defmodule ResearchAgent.Actions.Synthesize do
  @moduledoc """
  Jido Action to synthesize research into a final output.

  This action takes summarized sources and uses a provider
  to create a comprehensive, well-structured research report.
  """

  use Jido.Action,
    name: "synthesize",
    description: "Synthesize research sources into final output",
    schema: [
      sources: [type: :list, required: true, doc: "List of summarized sources"],
      query: [type: :map, required: true, doc: "Original research query"],
      provider: [
        type: :atom,
        required: false,
        default: :claude,
        doc: "Provider to use for synthesis"
      ]
    ]

  alias ResearchAgent.{Query, Providers}

  @impl true
  def run(params, _context) do
    sources = params.sources
    query = build_query(params.query)
    provider = params.provider
    module = resolve_provider(provider)

    if module.available?() do
      case module.synthesize(sources, query) do
        {:ok, result} ->
          {:ok,
           Map.merge(result, %{
             query_id: query.id,
             source_count: length(sources)
           })}

        {:error, reason} ->
          {:error, {:synthesis_failed, reason}}
      end
    else
      {:error, {:provider_unavailable, provider}}
    end
  end

  defp build_query(%Query{} = query), do: query

  defp build_query(params) when is_map(params) do
    Query.new(
      params[:topic] || params["topic"],
      depth: params[:depth] || params["depth"] || :quick,
      include_citations: params[:include_citations] || params["include_citations"] || true
    )
  end

  defp resolve_provider(:gemini), do: Providers.Gemini
  defp resolve_provider(:claude), do: Providers.Claude
end
