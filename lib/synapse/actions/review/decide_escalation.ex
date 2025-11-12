defmodule Synapse.Actions.Review.DecideEscalation do
  @moduledoc """
  Determines whether a critic review should be escalated to a human reviewer or
  auto-approved.

  The action inspects the critic's confidence score plus the `should_escalate`
  flag emitted by `Synapse.Actions.CriticReview`. Callers can override the
  escalation threshold per request.
  """

  use Jido.Action,
    name: "decide_escalation",
    description: "Decides whether to escalate a critic review",
    schema: [
      review: [type: :map, required: true, doc: "CriticReview payload"],
      threshold: [type: :float, default: 0.7, doc: "Confidence threshold"],
      metadata: [type: :map, default: %{}, doc: "Optional contextual metadata"]
    ]

  @impl true
  def run(%{review: review} = params, _context) do
    threshold = Map.get(params, :threshold, 0.7)
    confidence = Map.get(review, :confidence, 0.0)
    escalate_flag = Map.get(review, :should_escalate, false)

    {decision, reason} =
      cond do
        escalate_flag -> {:escalate, "Critic requested escalation"}
        confidence < threshold -> {:escalate, "Confidence #{confidence} below #{threshold}"}
        true -> {:auto_approve, "Confidence #{confidence} meets threshold"}
      end

    result = %{
      decision: decision,
      escalate?: decision == :escalate,
      reason: reason,
      confidence: confidence,
      review: review,
      metadata: Map.get(params, :metadata, %{})
    }

    {:ok, result}
  end
end
