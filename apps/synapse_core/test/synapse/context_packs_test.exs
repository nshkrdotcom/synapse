defmodule Synapse.ContextPacksTest do
  use ExUnit.Case, async: true

  alias Synapse.ContextPacks

  test "lists immutable AppKit retrieval snapshots" do
    assert {:ok, [pack]} = ContextPacks.list_context_packs()
    assert pack.ref == "proof-token://synapse/test-snapshot"
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
  end

  test "reports durable AppKit context surface status" do
    assert %{
             status: :durable_readback,
             public_surface: "AppKit.OperatorSurface"
           } = ContextPacks.surface_status()
  end
end
