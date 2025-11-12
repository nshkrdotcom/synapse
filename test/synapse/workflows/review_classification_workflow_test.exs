defmodule Synapse.Workflows.ReviewClassificationWorkflowTest do
  use Synapse.SupertesterCase, async: true

  alias Synapse.Workflows.ReviewClassificationWorkflow

  test "classifies deep review for large diffs" do
    {:ok, result} =
      ReviewClassificationWorkflow.classify(%{
        review_id: "rev-123",
        files_changed: 120,
        labels: [],
        intent: "feature",
        risk_factor: 0.1
      })

    assert result.path == :deep_review
    assert result.review_id == "rev-123"
    assert is_binary(result.rationale)
  end

  test "returns validation error when payload not a map" do
    assert {:error, %Jido.Error{type: :validation_error}} =
             ReviewClassificationWorkflow.classify(nil)
  end
end
