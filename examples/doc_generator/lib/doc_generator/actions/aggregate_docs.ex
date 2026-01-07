defmodule DocGenerator.Actions.AggregateDocs do
  @moduledoc """
  Jido Action to aggregate documentation from multiple providers.

  Combines results from different providers, handling successes and failures,
  and produces a merged documentation output.
  """

  use Jido.Action,
    name: "aggregate_docs",
    description: "Aggregate documentation results from multiple providers",
    schema: [
      results: [
        type: {:list, :any},
        required: true,
        doc: "List of {provider, result} tuples from generation"
      ],
      module: [type: :atom, required: true, doc: "Module being documented"],
      strategy: [
        type: :atom,
        required: false,
        doc: "Merge strategy: :combine, :best, :consensus"
      ]
    ]

  @impl true
  def run(params, _context) do
    results = params.results
    module = params.module
    strategy = params[:strategy] || :combine

    # Separate successful and failed results
    {successful, failed} =
      Enum.split_with(results, fn {_provider, result} ->
        match?({:ok, _}, result) or match?(%{content: _}, result)
      end)

    # Extract content from successful results
    provider_docs =
      successful
      |> Enum.map(fn {provider, result} ->
        content = extract_content(result)
        {provider, content}
      end)
      |> Map.new()

    # Apply merge strategy
    merged_content = merge_content(provider_docs, strategy)

    {:ok,
     %{
       module: module,
       merged: merged_content,
       individual: provider_docs,
       success_count: length(successful),
       failure_count: length(failed),
       providers: Map.keys(provider_docs),
       failed_providers: Enum.map(failed, fn {provider, _} -> provider end)
     }}
  end

  defp extract_content({:ok, %{content: content}}), do: content
  defp extract_content(%{content: content}), do: content
  defp extract_content({:ok, content}) when is_binary(content), do: content
  defp extract_content(_), do: ""

  defp merge_content(provider_docs, :combine) when map_size(provider_docs) == 0 do
    "No documentation generated."
  end

  defp merge_content(provider_docs, :combine) do
    provider_docs
    |> Enum.map(fn {provider, content} ->
      """
      ## Documentation from #{format_provider(provider)}

      #{content}
      """
    end)
    |> Enum.join("\n\n---\n\n")
  end

  defp merge_content(provider_docs, :best) do
    # Select the longest/most comprehensive documentation
    provider_docs
    |> Enum.max_by(fn {_provider, content} -> String.length(content) end, fn -> {nil, ""} end)
    |> elem(1)
  end

  defp merge_content(provider_docs, :consensus) do
    # For now, just combine them
    # A real implementation might use AI to synthesize a consensus
    merge_content(provider_docs, :combine)
  end

  defp format_provider(:claude), do: "Claude (Technical)"
  defp format_provider(:codex), do: "Codex (Code Examples)"
  defp format_provider(:gemini), do: "Gemini (Clear Explanations)"
  defp format_provider(other), do: to_string(other)
end
