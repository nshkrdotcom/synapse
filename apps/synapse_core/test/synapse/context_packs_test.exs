defmodule Synapse.ContextPacksTest do
  use ExUnit.Case, async: true

  alias Synapse.ContextPacks

  test "lists fixture-backed context packs" do
    assert [%{id: "phase-3"}] = ContextPacks.list_context_packs()
  end

  test "returns all memory disposition buckets" do
    assert {:ok, pack} = ContextPacks.get_context_pack("phase-3")

    assert [%{state: :included}] = pack.included
    assert [%{state: :denied}] = pack.denied
    assert [%{state: :stale}] = pack.stale
    assert [%{state: :revoked}] = pack.revoked
    assert [%{state: :candidate}] = pack.candidates
  end

  test "reports fixture-backed context surface status" do
    assert %{
             status: :fixture_backed,
             public_surface: :not_finalized
           } = ContextPacks.surface_status()
  end
end
