defmodule ReviewBot.Actions.AggregateReviews do
  @moduledoc """
  Jido Action to aggregate results from multiple providers.
  """

  use Jido.Action,
    name: "aggregate_reviews",
    description: "Aggregate results from multiple code review providers",
    schema: [
      results: [
        type: {:list, :map},
        required: true,
        doc: "List of {provider, result} tuples from review actions"
      ],
      review_id: [type: :integer, required: false, doc: "Review database ID"]
    ]

  alias ReviewBot.Reviews

  @impl true
  def run(params, _context) do
    results = params.results
    review_id = params[:review_id]

    # Filter successful results
    successful_results =
      results
      |> Enum.filter(fn {_provider, result} ->
        match?({:ok, _}, result) or match?(%{provider: _}, result)
      end)
      |> Enum.map(fn
        {provider, {:ok, result}} -> {provider, result}
        {provider, result} when is_map(result) -> {provider, result}
      end)

    # Calculate aggregate metrics
    combined = build_combined_analysis(successful_results)

    # Update database if review_id provided
    if review_id do
      case Reviews.get_review!(review_id) do
        nil ->
          :ok

        review ->
          Reviews.update_review(review, %{
            status: :completed,
            results: combined
          })

          # Broadcast completion
          Phoenix.PubSub.broadcast(
            ReviewBot.PubSub,
            "review:#{review_id}",
            {:review_complete, combined}
          )
      end
    end

    {:ok, combined}
  end

  defp build_combined_analysis(results) do
    individual = Map.new(results)

    scores =
      results
      |> Enum.map(fn {_provider, result} ->
        get_in(result, [:analysis, :quality_score]) || 0
      end)

    avg_score =
      if Enum.empty?(scores) do
        0
      else
        Enum.sum(scores) / length(scores)
      end

    all_issues =
      results
      |> Enum.flat_map(fn {provider, result} ->
        issues = get_in(result, [:analysis, :issues]) || []
        Enum.map(issues, &Map.put(&1, :provider, provider))
      end)

    %{
      individual: individual,
      combined: %{
        average_score: Float.round(avg_score, 1),
        total_issues: length(all_issues),
        all_issues: all_issues,
        provider_count: length(results),
        consensus: build_consensus(results)
      },
      summary: build_summary(results, avg_score)
    }
  end

  defp build_consensus(results) do
    issue_types =
      results
      |> Enum.flat_map(fn {_provider, result} ->
        issues = get_in(result, [:analysis, :issues]) || []
        Enum.map(issues, & &1[:type])
      end)
      |> Enum.frequencies()

    common_issues =
      issue_types
      |> Enum.filter(fn {_type, count} -> count >= 2 end)
      |> Enum.map(fn {type, count} -> {type, count} end)
      |> Map.new()

    %{
      common_issues: common_issues,
      total_providers: length(results)
    }
  end

  defp build_summary(results, avg_score) do
    provider_names = Enum.map(results, fn {provider, _} -> provider end)

    quality =
      cond do
        avg_score >= 85 -> "excellent"
        avg_score >= 75 -> "good"
        avg_score >= 65 -> "acceptable"
        true -> "needs improvement"
      end

    """
    Reviewed by #{length(results)} providers (#{Enum.join(provider_names, ", ")}).
    Overall quality: #{quality} (score: #{Float.round(avg_score, 1)}/100).
    #{summarize_common_issues(results)}
    """
  end

  defp summarize_common_issues(results) do
    issue_types =
      results
      |> Enum.flat_map(fn {_provider, result} ->
        issues = get_in(result, [:analysis, :issues]) || []
        Enum.map(issues, & &1[:type])
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_type, count} -> count >= 2 end)
      |> Enum.sort_by(fn {_type, count} -> -count end)
      |> Enum.take(3)

    if Enum.empty?(issue_types) do
      "No common issues identified across providers."
    else
      types = Enum.map(issue_types, fn {type, _} -> type end)
      "Common concerns: #{Enum.join(types, ", ")}."
    end
  end
end
