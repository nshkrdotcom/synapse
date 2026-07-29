defmodule Synapse.MemoryTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.{MemoryFragmentProjection, MemoryFragmentProvenance}
  alias Synapse.Memory

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
    assert Enum.all?(memories, &(not Map.has_key?(&1, :body)))
    assert Enum.all?(memories, &(not Map.has_key?(&1, :payload)))
  end

  test "returns a single memory projection without raw payloads" do
    route_id = URI.encode_www_form("memory://durable/project-fact")
    assert {:ok, memory} = Memory.get_memory(route_id)

    assert memory.content_hash ==
             "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    assert memory.projection.fragment_ref == "memory://durable/project-fact"
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
