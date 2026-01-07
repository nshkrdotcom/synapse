defmodule Synapse.Domains.CodeReview.Actions.GenerateSummary do
  @moduledoc """
  Generates a consolidated review summary from specialist findings.

  Aggregates results from SecurityAgent and PerformanceAgent, computes
  overall severity, generates recommendations, and determines if escalation
  is required.

  Returns a summary payload conforming to the `review.summary` signal schema.
  """

  use Jido.Action,
    name: "generate_summary",
    description: "Synthesizes specialist findings into final review summary",
    schema: [
      review_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for this review"
      ],
      findings: [
        type: {:list, :map},
        required: true,
        doc: "Combined findings from all specialists"
      ],
      metadata: [
        type: :map,
        required: true,
        doc: "Review metadata including decision_path, specialists_resolved, duration_ms"
      ]
    ]

  require Logger

  @severity_order %{none: 0, low: 1, medium: 2, high: 3}

  @impl true
  def run(params, _context) do
    specialists_resolved = get_in(params.metadata, [:specialists_resolved]) || []
    decision_path = get_in(params.metadata, [:decision_path])

    status =
      cond do
        decision_path == :fast_path ->
          :complete

        specialists_resolved == [] ->
          :failed

        true ->
          :complete
      end

    severity = calculate_max_severity(params.findings)
    sorted_findings = sort_findings_by_severity(params.findings)
    recommendations = extract_recommendations(params.findings)
    escalations = generate_escalations(params.metadata, params.findings, status, severity)

    result = %{
      review_id: params.review_id,
      status: status,
      severity: severity,
      findings: sorted_findings,
      recommendations: recommendations,
      escalations: escalations,
      metadata: params.metadata
    }

    Logger.info("Review summary generated",
      review_id: params.review_id,
      status: status,
      severity: severity,
      findings_count: Enum.count(sorted_findings)
    )

    {:ok, result}
  end

  defp calculate_max_severity([]), do: :none

  defp calculate_max_severity(findings) do
    findings
    |> Enum.map(& &1.severity)
    |> Enum.max_by(&Map.get(@severity_order, &1, 0))
  end

  defp sort_findings_by_severity(findings) do
    Enum.sort_by(
      findings,
      & &1.severity,
      fn sev1, sev2 ->
        Map.get(@severity_order, sev1, 0) >= Map.get(@severity_order, sev2, 0)
      end
    )
  end

  defp extract_recommendations(findings) do
    findings
    |> Enum.filter(&(&1[:recommendation] != nil))
    |> Enum.map(& &1.recommendation)
    |> Enum.uniq()
  end

  defp generate_escalations(metadata, _findings, :failed, _severity) do
    specialists_resolved = Map.get(metadata, :specialists_resolved, [])

    if specialists_resolved == [] do
      ["No specialists responded - manual review required"]
    else
      ["Review failed - please investigate"]
    end
  end

  defp generate_escalations(_metadata, findings, :complete, :high) do
    if findings != [] do
      ["High severity findings detected - recommend thorough human review"]
    else
      []
    end
  end

  defp generate_escalations(_metadata, _findings, :complete, :medium) do
    []
  end

  defp generate_escalations(_metadata, _findings, :complete, _severity) do
    []
  end
end
