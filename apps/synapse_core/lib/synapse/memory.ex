defmodule Synapse.Memory do
  @moduledoc """
  Product-safe memory projections over AppKit's DTO-only memory surface.
  """

  alias AppKit.MemorySurface

  @raw_keys [
    :body,
    :raw_body,
    :payload,
    :raw_payload,
    "body",
    "raw_body",
    "payload",
    "raw_payload"
  ]

  @fixture_memories [
    %{
      id: "included-project-fact",
      state: :included,
      title: "Included project fact",
      memory_ref: "memory://fixture/included-project-fact",
      evidence_ref: "memory-evidence://fixture/included-project-fact",
      content_hash: "sha256:included-project-fact",
      redaction_policy_ref: "redaction://synapse/hash-only",
      redacted_excerpt: "Project fact available through a redacted projection.",
      provenance: "context-pack://fixture/phase-3",
      reason_codes: []
    },
    %{
      id: "denied-sensitive-fact",
      state: :denied,
      title: "Denied sensitive fact",
      memory_ref: "memory://fixture/denied-sensitive-fact",
      evidence_ref: "memory-evidence://fixture/denied-sensitive-fact",
      content_hash: "sha256:denied-sensitive-fact",
      redaction_policy_ref: "redaction://synapse/no-export",
      redacted_excerpt: nil,
      provenance: "context-pack://fixture/phase-3",
      reason_codes: ["authority_denied", "redaction_no_export"]
    },
    %{
      id: "stale-run-note",
      state: :stale,
      title: "Stale run note",
      memory_ref: "memory://fixture/stale-run-note",
      evidence_ref: "memory-evidence://fixture/stale-run-note",
      content_hash: "sha256:stale-run-note",
      redaction_policy_ref: "redaction://synapse/hash-only",
      redacted_excerpt: "Older note retained for provenance only.",
      provenance: "context-pack://fixture/older",
      reason_codes: ["superseded"]
    },
    %{
      id: "revoked-agent-note",
      state: :revoked,
      title: "Revoked agent note",
      memory_ref: "memory://fixture/revoked-agent-note",
      evidence_ref: "memory-evidence://fixture/revoked-agent-note",
      content_hash: "sha256:revoked-agent-note",
      redaction_policy_ref: "redaction://synapse/no-export",
      redacted_excerpt: nil,
      provenance: "context-pack://fixture/revoked",
      reason_codes: ["revoked"]
    },
    %{
      id: "candidate-learning",
      state: :candidate,
      title: "Candidate learning",
      memory_ref: "memory://fixture/candidate-learning",
      evidence_ref: "memory-evidence://fixture/candidate-learning",
      content_hash: "sha256:candidate-learning",
      redaction_policy_ref: "redaction://synapse/redacted-excerpt",
      redacted_excerpt: "Candidate memory awaiting promotion review.",
      provenance: "review://fixture/fixture-review",
      reason_codes: ["promotion_review_required"]
    }
  ]

  @spec list_memories(keyword()) :: [map()]
  def list_memories(_opts \\ []) do
    Enum.map(@fixture_memories, &projection_view!/1)
  end

  @spec get_memory(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_memory(id, _opts \\ []) when is_binary(id) do
    case Enum.find(@fixture_memories, &(&1.id == id)) do
      nil -> {:error, :memory_projection_not_found}
      memory -> {:ok, projection_view!(memory)}
    end
  end

  @spec write_feedback(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def write_feedback(attrs, _opts \\ []) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs) do
      {:error, :memory_feedback_write_disabled}
    end
  end

  @spec feedback_status() :: map()
  def feedback_status do
    %{
      status: :disabled,
      reason: :dto_only_memory_surface,
      required_surface: "AppKit product memory write backend"
    }
  end

  defp projection_view!(attrs) do
    {:ok, projection} = MemorySurface.projection(projection_attrs(attrs))
    Map.put(attrs, :projection, projection)
  end

  defp projection_attrs(attrs) do
    %{
      memory_ref: %{
        memory_id: attrs.id,
        tenant_ref: "tenant://default",
        tier: memory_tier(attrs.state),
        revision: 1,
        scope_key: %{
          tenant_ref: "tenant://default",
          installation_ref: "installation://default",
          subject_ref: "subject://fixture/phase-3",
          run_ref: "run://fixture/phase-3"
        }
      },
      evidence_ref: %{
        memory_id: attrs.id,
        evidence_hash: attrs.content_hash,
        evidence_owner_ref: attrs.provenance,
        release_manifest_ref: "release://synapse/fixture",
        redaction_policy_ref: attrs.redaction_policy_ref
      },
      content_hash: attrs.content_hash,
      redaction_policy_ref: attrs.redaction_policy_ref,
      redacted_excerpt: attrs.redacted_excerpt
    }
  end

  defp memory_tier(:candidate), do: :working
  defp memory_tier(_state), do: :semantic

  defp reject_raw_payload(attrs) do
    case Enum.find(@raw_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_memory_payload_forbidden, key}}
    end
  end
end
