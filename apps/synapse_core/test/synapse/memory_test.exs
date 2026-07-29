defmodule Synapse.MemoryTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.{MemoryFragmentProjection, MemoryFragmentProvenance}
  alias Synapse.Memory
  alias Synapse.Memory.Entry

  test "lists product-safe durable AppKit memory projections" do
    assert {:ok, memories} = Memory.list_memories()

    assert Enum.map(memories, & &1.state) == [
             :included,
             :stale,
             :revoked,
             :candidate,
             :degraded
           ]

    assert Enum.all?(memories, &match?(%MemoryFragmentProjection{}, &1.projection))
    assert Enum.all?(memories, &match?(%Entry{}, &1))
    assert Enum.all?(memories, &(not Map.has_key?(&1, :body)))
    assert Enum.all?(memories, &(not Map.has_key?(&1, :payload)))

    assert Enum.map(memories, & &1.memory_class) == [
             :episodic,
             :episodic,
             :episodic,
             :working,
             :episodic
           ]

    included = hd(memories)
    assert included.content_artifact_ref == "artifact://synapse/memory/project-fact"
    assert included.snapshot.retrieval_snapshot_ref == "snapshot://synapse/test-snapshot/7"
    assert included.lifecycle.retention_state == :retained
    assert included.lifecycle.deletion_state == :active
    assert included.lifecycle.reindex_state == :indexed
    assert included.lifecycle.index_revision == 12

    revoked = Enum.find(memories, &(&1.state == :revoked))
    assert revoked.lifecycle.retention_state == :deleted
    assert revoked.lifecycle.deletion_state == :tombstoned
    assert revoked.lifecycle.deletion_reason == "owner_revoked"

    degraded = Enum.find(memories, &(&1.state == :degraded))
    assert degraded.lifecycle.deletion_state == :unknown
    assert degraded.lifecycle.reindex_state == :degraded
  end

  test "returns a single memory projection without raw payloads" do
    route_id = URI.encode_www_form("memory://durable/project-fact")
    assert {:ok, memory} = Memory.get_memory(route_id)

    assert memory.content_hash ==
             "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    assert memory.projection.fragment_ref == "memory://durable/project-fact"
    assert memory.content_artifact_ref == "artifact://synapse/memory/project-fact"
    assert memory.provenance_label == "provenance://outer-brain/project-fact"
    assert %MemoryFragmentProvenance{} = memory.provenance_projection

    assert memory.provenance_projection.source_contract_name ==
             "OuterBrain.MemoryContextProvenance.v2"

    refute Map.has_key?(memory, :body)
    refute Map.has_key?(memory, :payload)
  end

  test "rejects raw memory feedback payloads" do
    assert {:error, {:raw_memory_payload_forbidden, :body}} =
             Memory.write_feedback(%{body: "raw memory text"})

    assert {:error, {:raw_memory_payload_forbidden, "payload"}} =
             Memory.write_feedback(%{"payload" => "raw payload"})
  end

  test "keeps feedback writes outside the current journey" do
    assert {:error, :memory_feedback_write_not_in_current_journey} =
             Memory.write_feedback(%{
               memory_ref: "memory://durable/project-fact",
               feedback_kind: "helpful"
             })

    assert %{status: :disabled, reason: :memory_feedback_write_not_in_current_journey} =
             Memory.feedback_status()
  end

  test "reports durable readback only when a proof token is configured" do
    assert %{
             status: :durable_readback,
             public_surface: "AppKit.OperatorSurface",
             proof_token_ref: "proof-token://synapse/test-snapshot"
           } = Memory.surface_status()

    assert %{status: :unavailable, reason: :memory_proof_token_unavailable} =
             Memory.surface_status(memory_proof_token_ref: nil)
  end
end
