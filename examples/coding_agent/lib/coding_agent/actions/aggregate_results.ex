defmodule CodingAgent.Actions.AggregateResults do
  @moduledoc """
  Jido Action to aggregate results from multiple providers.
  """

  use Jido.Action,
    name: "aggregate_results",
    description: "Aggregate results from multiple provider executions",
    schema: [
      results: [type: {:list, :any}, required: true, doc: "List of {provider, result} tuples"],
      task: [type: :map, required: true, doc: "Original task"]
    ]

  @impl true
  def run(params, _context) do
    results = params.results
    task = params.task

    # Separate successful and failed results
    {successful, failed} =
      Enum.split_with(results, fn {_provider, result} ->
        case result do
          {:ok, _} -> true
          %{content: content} when is_binary(content) -> true
          _ -> false
        end
      end)

    # Build combined content from successful results
    combined_content =
      successful
      |> Enum.map(fn {provider, result} ->
        content = extract_content(result)
        "## #{format_provider(provider)}\n\n#{content}"
      end)
      |> Enum.join("\n\n---\n\n")

    # Build individual results map
    individual =
      results
      |> Enum.map(fn {provider, result} ->
        {provider, format_result(result)}
      end)
      |> Map.new()

    {:ok,
     %{
       combined: combined_content,
       individual: individual,
       success_count: length(successful),
       failure_count: length(failed),
       total_count: length(results),
       task_id: get_task_id(task)
     }}
  end

  defp extract_content({:ok, %{content: content}}), do: content
  defp extract_content(%{content: content}), do: content
  defp extract_content(_), do: "(no content)"

  defp format_provider(:claude), do: "Claude"
  defp format_provider(:codex), do: "Codex"
  defp format_provider(:gemini), do: "Gemini"
  defp format_provider(other), do: to_string(other)

  defp format_result({:ok, result}), do: %{status: :ok, result: result}
  defp format_result({:error, reason}), do: %{status: :error, error: reason}
  defp format_result(result) when is_map(result), do: %{status: :ok, result: result}
  defp format_result(other), do: %{status: :unknown, raw: other}

  defp get_task_id(%{id: id}), do: id
  defp get_task_id(%{"id" => id}), do: id
  defp get_task_id(_), do: nil
end
