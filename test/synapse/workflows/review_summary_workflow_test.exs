defmodule Synapse.Workflows.ReviewSummaryWorkflowTest do
  use Synapse.SupertesterCase, async: true

  alias Synapse.Workflows.ReviewSummaryWorkflow

  test "generates summary with metadata preserved" do
    metadata = %{
      decision_path: :deep_review,
      specialists_resolved: ["security_specialist"],
      duration_ms: 1_250
    }

    {:ok, summary} =
      ReviewSummaryWorkflow.generate(%{
        review_id: "rev-456",
        findings: [
          %{type: :sql_injection, severity: :high, recommendation: "Use parameterized queries"},
          %{type: :n_plus_one, severity: :medium}
        ],
        metadata: metadata
      })

    assert summary.review_id == "rev-456"
    assert summary.metadata.decision_path == :deep_review
    assert summary.status == :complete
    assert Enum.any?(summary.findings, &(&1.type == :sql_injection))
  end

  test "returns validation error when input is not a map" do
    assert {:error, %Jido.Error{type: :validation_error}} =
             ReviewSummaryWorkflow.generate("invalid")
  end
end
