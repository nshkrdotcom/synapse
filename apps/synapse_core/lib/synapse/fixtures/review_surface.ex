defmodule Synapse.Fixtures.ReviewSurface do
  @moduledoc """
  Deterministic review surface for fixture-backed Synapse phases.
  """

  alias AppKit.Core.{ActionResult, PageResult}

  @reviews [
    %{
      id: "fixture-review",
      decision_id: "decision://fixture/fixture-review",
      decision_kind: "operator_review",
      run_ref: "run://fixture/phase-3",
      subject_ref: "subject://fixture/phase-3",
      title: "Review fixture governed agent run",
      status: :pending,
      authority_state: :authorized,
      reviewer_role: "operator",
      reason_codes: ["review_required", "external_effect_blocked_until_review"],
      evidence_refs: ["receipt://fixture/start/phase-3"],
      context_pack_ref: "context-pack://fixture/phase-3",
      memory_posture: :disabled,
      tool_posture: :fixture_projected,
      stale?: false,
      denied?: false
    },
    %{
      id: "fixture-denied-review",
      decision_id: "decision://fixture/denied-review",
      decision_kind: "operator_review",
      run_ref: "run://fixture/denied",
      subject_ref: "subject://fixture/denied",
      title: "Denied fixture review",
      status: :blocked,
      authority_state: :denied,
      reviewer_role: "operator",
      reason_codes: ["authority_denied", "stale_installation_revision"],
      evidence_refs: ["receipt://fixture/denied"],
      context_pack_ref: "context-pack://fixture/denied",
      memory_posture: :disabled,
      tool_posture: :denied,
      stale?: true,
      denied?: true
    }
  ]

  def list_pending(_context, _page_request, _opts) do
    PageResult.new(%{
      entries: @reviews,
      total_count: length(@reviews),
      has_more: false,
      metadata: %{source: :fixture}
    })
  end

  def get_review(_context, decision_ref, _opts) do
    review =
      Enum.find(@reviews, fn review ->
        review.decision_id == decision_ref.id or review.id == decision_ref.id
      end)

    case review do
      nil -> {:error, :fixture_review_not_found}
      review -> {:ok, review}
    end
  end

  def record_decision(_context, decision_ref, attrs, _opts) do
    decision = Map.get(attrs, :decision) || Map.get(attrs, "decision")

    ActionResult.new(%{
      status: :accepted,
      message: "Fixture decision #{decision} recorded",
      metadata: %{
        decision_id: decision_ref.id,
        decision: decision,
        source: :fixture
      }
    })
  end

  def record_decision_by_id(context, decision_id, attrs, opts) when is_binary(decision_id) do
    {:ok, decision_ref} =
      AppKit.Core.DecisionRef.new(%{
        id: decision_id,
        decision_kind: "operator_review"
      })

    record_decision(context, decision_ref, attrs, opts)
  end
end
