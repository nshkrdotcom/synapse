defmodule ResearchAgent.Actions.FetchContent do
  @moduledoc """
  Jido Action to fetch content from search results.

  This action takes search results and converts them into
  Source structs with reliability scoring.
  """

  use Jido.Action,
    name: "fetch_content",
    description: "Fetch and process content from search results",
    schema: [
      search_results: [type: :map, required: true, doc: "Search results from SearchWeb action"],
      reliability_threshold: [
        type: :float,
        required: false,
        default: 0.6,
        doc: "Minimum reliability score"
      ]
    ]

  alias ResearchAgent.Source

  @impl true
  def run(params, _context) do
    search_results = params.search_results
    threshold = params.reliability_threshold

    results = search_results[:results] || search_results["results"] || []

    sources =
      results
      |> Enum.map(&build_source/1)
      |> Enum.map(&Source.with_reliability/1)
      |> Enum.filter(&filter_by_reliability(&1, threshold))
      |> Enum.sort_by(& &1.reliability_score, :desc)

    {:ok,
     %{
       sources: sources,
       total_found: length(results),
       filtered_count: length(sources),
       reliability_threshold: threshold
     }}
  end

  defp build_source(result) when is_map(result) do
    Source.new(
      result[:url] || result["url"],
      result[:snippet] || result["snippet"] || "",
      title: result[:title] || result["title"]
    )
  end

  defp filter_by_reliability(source, threshold) do
    source.reliability_score >= threshold
  end
end
