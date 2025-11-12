defmodule Synapse.Signal.ReviewResult do
  @moduledoc """
  Schema for `review.result` signals emitted by specialist agents.
  """

  use Synapse.Signal.Schema,
    schema: [
      review_id: [
        type: :string,
        required: true,
        doc: "Review identifier the findings belong to"
      ],
      agent: [
        type: :string,
        required: true,
        doc: "Logical specialist identifier (e.g., \"security_specialist\")"
      ],
      confidence: [
        type: :float,
        default: 0.0,
        doc: "Confidence score for the findings"
      ],
      findings: [
        type: {:list, :map},
        default: [],
        doc: "List of findings detected by the specialist"
      ],
      should_escalate: [
        type: :boolean,
        default: false,
        doc: "Signals whether human escalation is recommended"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Additional execution metadata emitted by the specialist"
      ]
    ]
end
