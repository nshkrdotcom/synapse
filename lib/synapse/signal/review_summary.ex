defmodule Synapse.Signal.ReviewSummary do
  @moduledoc """
  Schema for `review.summary` signals emitted by the coordinator.
  """

  use Synapse.Signal.Schema,
    schema: [
      review_id: [
        type: :string,
        required: true,
        doc: "Review identifier"
      ],
      status: [
        type: :atom,
        default: :complete,
        doc: "Overall status for the review workflow"
      ],
      severity: [
        type: :atom,
        default: :none,
        doc: "Max severity across all findings"
      ],
      findings: [
        type: {:list, :map},
        default: [],
        doc: "Combined findings ordered by severity"
      ],
      recommendations: [
        type: {:list, :any},
        default: [],
        doc: "Recommended actions for follow-up"
      ],
      escalations: [
        type: {:list, :string},
        default: [],
        doc: "Reason(s) for triggering escalation"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Coordinator metadata (decision path, runtime stats, etc.)"
      ]
    ]
end
