defmodule Synapse.ContextPacks do
  @moduledoc """
  Product-safe context-pack projections.
  """

  @fixture_packs [
    %{
      id: "phase-3",
      ref: "context-pack://fixture/phase-3",
      mode: :run_context,
      run_ref: "run://fixture/phase-3",
      trace_id: "33333333333333333333333333333333",
      context_hash: "sha256:context-pack-phase-3",
      redaction_policy_ref: "redaction://synapse/hash-only",
      included: [
        %{
          ref: "memory://fixture/included-project-fact",
          state: :included,
          evidence_ref: "memory-evidence://fixture/included-project-fact"
        }
      ],
      denied: [
        %{
          ref: "memory://fixture/denied-sensitive-fact",
          state: :denied,
          reason_codes: ["authority_denied", "redaction_no_export"]
        }
      ],
      stale: [
        %{
          ref: "memory://fixture/stale-run-note",
          state: :stale,
          reason_codes: ["superseded"]
        }
      ],
      revoked: [
        %{
          ref: "memory://fixture/revoked-agent-note",
          state: :revoked,
          reason_codes: ["revoked"]
        }
      ],
      candidates: [
        %{
          ref: "memory://fixture/candidate-learning",
          state: :candidate,
          reason_codes: ["promotion_review_required"]
        }
      ]
    }
  ]

  @spec list_context_packs(keyword()) :: [map()]
  def list_context_packs(_opts \\ []), do: @fixture_packs

  @spec get_context_pack(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_context_pack(id_or_ref, _opts \\ []) when is_binary(id_or_ref) do
    case Enum.find(@fixture_packs, fn pack -> pack.id == id_or_ref or pack.ref == id_or_ref end) do
      nil -> {:error, :context_pack_not_found}
      pack -> {:ok, pack}
    end
  end

  @spec surface_status() :: map()
  def surface_status do
    %{
      status: :fixture_backed,
      public_surface: :not_finalized,
      current_bridge: "AppKit context-pack bridge"
    }
  end
end
