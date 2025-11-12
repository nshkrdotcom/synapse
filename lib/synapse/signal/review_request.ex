defmodule Synapse.Signal.ReviewRequest do
  @moduledoc """
  Schema for `review.request` signals flowing through the router.
  """

  use Synapse.Signal.Schema,
    schema: [
      review_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the review"
      ],
      diff: [
        type: :string,
        default: "",
        doc: "Unified diff or snippet under review"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Arbitrary metadata describing the review target"
      ],
      files_changed: [
        type: :integer,
        default: 0,
        doc: "Count of files changed in the review"
      ],
      labels: [
        type: {:list, :string},
        default: [],
        doc: "Labels or tags attached to the review"
      ],
      intent: [
        type: :string,
        default: "feature",
        doc: "Intent label used for routing"
      ],
      risk_factor: [
        type: :float,
        default: 0.0,
        doc: "Risk multiplier used during classification"
      ],
      files: [
        type: {:list, :string},
        default: [],
        doc: "List of files referenced by the review"
      ],
      language: [
        type: :string,
        default: "elixir",
        doc: "Primary language hint for the review"
      ]
    ]
end
