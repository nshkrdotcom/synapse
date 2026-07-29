defmodule Synapse.ContextPacksTest do
  use ExUnit.Case, async: true

  alias Synapse.ContextPacks
  alias Synapse.ContextPacks.Pack

  test "lists immutable AppKit retrieval snapshots" do
    assert {:ok, [pack]} = ContextPacks.list_context_packs()
    assert %Pack{} = pack
    assert pack.ref == "proof-token://synapse/test-snapshot"
    assert pack.retrieval_snapshot_ref == "snapshot://synapse/test-snapshot/7"

    assert pack.context_manifest_artifact_ref ==
             "artifact://synapse/context/test-snapshot"

    assert pack.working_memory_refs == ["memory://durable/candidate-learning"]

    assert length(pack.episodic_memory_refs) == 4
    assert pack.exclusion_refs == ["memory://durable/excluded-secret"]
    assert pack.feature_status == :durable_retrieval_snapshot
  end

  test "returns all memory disposition buckets" do
    id = URI.encode_www_form("proof-token://synapse/test-snapshot")
    assert {:ok, pack} = ContextPacks.get_context_pack(id)

    assert [%{state: :included}] = pack.included
    assert [] = pack.denied
    assert [%{state: :stale}] = pack.stale
    assert [%{state: :revoked}] = pack.revoked
    assert [%{state: :candidate}] = pack.candidates
    assert [%{state: :degraded}] = pack.degraded
    assert Enum.sort(pack.retention_states) == [:deleted, :retained]
    assert Enum.sort(pack.deletion_states) == [:active, :tombstoned, :unknown]
    assert Enum.sort(pack.reindex_states) == [:degraded, :indexed, :pending]
    assert pack.index_revision == 12
  end

  test "reports durable AppKit context surface status" do
    assert %{
             status: :durable_readback,
             public_surface: "AppKit.OperatorSurface"
           } = ContextPacks.surface_status()
  end
end
