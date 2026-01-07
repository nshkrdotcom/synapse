defmodule ResearchAgent.Actions.SearchWeb do
  @moduledoc """
  Jido Action to search the web for information using a provider.

  This action uses the configured provider to search for relevant
  sources based on the research query.
  """

  use Jido.Action,
    name: "search_web",
    description: "Search the web for research sources",
    schema: [
      query: [type: :map, required: true, doc: "Research query struct"],
      provider: [
        type: :atom,
        required: false,
        default: :gemini,
        doc: "Provider to use for search"
      ]
    ]

  alias ResearchAgent.{Query, Providers}

  @impl true
  def run(params, _context) do
    query = build_query(params.query)
    provider = params.provider
    module = resolve_provider(provider)

    if module.available?() do
      case module.search(query) do
        {:ok, results} ->
          {:ok, results}

        {:error, reason} ->
          {:error, {:search_failed, reason}}
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
      max_sources: params[:max_sources] || params["max_sources"] || 10,
      reliability_threshold:
        params[:reliability_threshold] || params["reliability_threshold"] || 0.6
    )
  end

  defp resolve_provider(:gemini), do: Providers.Gemini
  defp resolve_provider(:claude), do: Providers.Claude
end
