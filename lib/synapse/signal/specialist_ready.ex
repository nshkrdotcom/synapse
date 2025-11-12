defmodule Synapse.Signal.SpecialistReady do
  @moduledoc """
  Schema for `review.specialist_ready` signals emitted by specialists when
  they finish bootstrapping.
  """

  use Synapse.Signal.Schema,
    schema: [
      agent: [
        type: :string,
        required: true,
        doc: "Specialist identifier"
      ],
      router: [
        type: :atom,
        required: true,
        doc: "Router instance used by the specialist"
      ],
      timestamp: [
        type: :any,
        default: nil,
        doc: "UTC timestamp of readiness"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional readiness context (supervisor, runtime id, etc.)"
      ]
    ]
end
