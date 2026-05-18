defmodule Synapse.Arbitration do
  @moduledoc """
  Product-safe arbitration projections and final decision routing.
  """

  alias Synapse.Reviews

  @session %{
    id: "phase-7",
    ref: "arbitration://synapse/team/phase-7",
    team_ref: "coordination-run://synapse/team/phase-7",
    state: :consensus_pending,
    consensus_posture: :review_required,
    quorum: %{required_count: 2, arrived_count: 2, state: :met},
    positions: [
      %{
        id: "planner",
        role_ref: "role://synapse/planner",
        position_ref: "position://synapse/planner/phase-7",
        stance: :accept,
        evidence_refs: ["evidence://synapse/planner/proposal"]
      },
      %{
        id: "reviewer",
        role_ref: "role://synapse/reviewer",
        position_ref: "position://synapse/reviewer/phase-7",
        stance: :needs_review,
        evidence_refs: ["evidence://synapse/reviewer/blocker"]
      },
      %{
        id: "verifier",
        role_ref: "role://synapse/verifier",
        position_ref: "position://synapse/verifier/phase-7",
        stance: :accept_with_conditions,
        evidence_refs: ["evidence://synapse/verifier/check"]
      }
    ],
    memory_write_status: %{
      status: :disabled,
      reason: :memory_write_grant_required,
      required_grant_ref: "memory-grant://synapse/team/write"
    },
    final_decision_route: "AppKit.ReviewSurface"
  }

  @spec list_sessions(keyword()) :: [map()]
  def list_sessions(_opts \\ []), do: [@session]

  @spec get_session(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_session(id_or_ref, _opts \\ []) when is_binary(id_or_ref) do
    if id_or_ref in [@session.id, @session.ref] do
      {:ok, @session}
    else
      {:error, :arbitration_session_not_found}
    end
  end

  @spec record_final_decision(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def record_final_decision(id_or_ref, attrs, opts \\ [])
      when is_binary(id_or_ref) and is_map(attrs) and is_list(opts) do
    with {:ok, _session} <- get_session(id_or_ref) do
      Reviews.record_decision(
        "arbitration-consensus",
        Map.put_new(attrs, "reason", "arbitration_consensus"),
        opts
      )
    end
  end
end
