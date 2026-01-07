defmodule ResearchAgent.Actions.Summarize do
  @moduledoc """
  Jido Action to summarize gathered content.

  This action takes a collection of sources and creates
  brief summaries for each one, preparing them for synthesis.
  """

  use Jido.Action,
    name: "summarize",
    description: "Summarize gathered research sources",
    schema: [
      sources: [type: :list, required: true, doc: "List of Source structs to summarize"],
      max_summary_length: [
        type: :integer,
        required: false,
        default: 500,
        doc: "Maximum characters per summary"
      ]
    ]

  alias ResearchAgent.Source

  @impl true
  def run(params, _context) do
    sources = params.sources
    max_length = params.max_summary_length

    summarized =
      sources
      |> Enum.map(&add_summary(&1, max_length))

    {:ok,
     %{
       sources: summarized,
       summary_count: length(summarized)
     }}
  end

  defp add_summary(%Source{} = source, max_length) do
    summary = create_summary(source.content, max_length)
    %{source | summary: summary}
  end

  defp add_summary(source, max_length) when is_map(source) do
    content = source[:content] || source["content"] || source[:snippet] || source["snippet"] || ""
    summary = create_summary(content, max_length)

    source
    |> Map.put(:summary, summary)
    |> Map.put("summary", summary)
  end

  defp create_summary(content, max_length) when is_binary(content) do
    content
    |> String.trim()
    |> String.slice(0, max_length)
    |> then(fn text ->
      if String.length(content) > max_length do
        text <> "..."
      else
        text
      end
    end)
  end

  defp create_summary(_, _), do: ""
end
