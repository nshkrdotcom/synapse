defmodule Synapse.Actions.CriticReview do
  @moduledoc """
  Reviews code/output and provides confidence scoring.
  This is a simplified version - in production this would call an LLM or use learned patterns.
  """

  use Jido.Action,
    name: "critic_review",
    description: "Reviews code and provides confidence assessment",
    schema: [
      code: [type: :string, required: true, doc: "The code/output to review"],
      intent: [type: :string, required: true, doc: "What the code should accomplish"],
      constraints: [type: {:list, :string}, default: [], doc: "Constraints to check"]
    ]

  @impl true
  def run(params, _context) do
    # Simple heuristic-based review (placeholder for actual LLM/pattern matching)
    issues = detect_issues(params)
    confidence = calculate_confidence(params, issues)
    should_escalate = confidence < 0.7

    {:ok,
     %{
       confidence: confidence,
       issues: issues,
       recommendations: generate_recommendations(issues),
       should_escalate: should_escalate,
       reviewed_at: DateTime.utc_now()
     }}
  end

  defp detect_issues(params) do
    issues = []

    # Example heuristics
    issues =
      if String.length(params.code) < 5 do
        ["Code seems too short" | issues]
      else
        issues
      end

    issues =
      if String.contains?(params.code, "TODO") or String.contains?(params.code, "FIXME") do
        ["Contains TODO/FIXME markers" | issues]
      else
        issues
      end

    issues
  end

  defp calculate_confidence(_params, issues) do
    # Simple confidence calculation based on issues found
    base_confidence = 0.9
    penalty_per_issue = 0.1

    max(0.0, base_confidence - length(issues) * penalty_per_issue)
  end

  defp generate_recommendations([]), do: ["Code looks good"]

  defp generate_recommendations(issues) do
    Enum.map(issues, fn issue ->
      "Address: #{issue}"
    end)
  end
end
