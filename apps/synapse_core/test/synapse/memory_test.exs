defmodule Synapse.MemoryTest do
  use ExUnit.Case, async: true

  alias AppKit.MemorySurface.MemoryProjection
  alias Synapse.Memory

  test "lists fixture-backed redacted memory projections" do
    memories = Memory.list_memories()

    assert Enum.map(memories, & &1.state) == [
             :included,
             :denied,
             :stale,
             :revoked,
             :candidate
           ]

    assert Enum.all?(memories, &match?(%MemoryProjection{}, &1.projection))
  end

  test "returns a single memory projection without raw payloads" do
    assert {:ok, memory} = Memory.get_memory("included-project-fact")

    assert memory.projection.content_hash == "sha256:included-project-fact"
    assert memory.projection.redacted_excerpt =~ "redacted projection"
    refute Map.has_key?(memory, :body)
    refute Map.has_key?(memory, :payload)
  end

  test "rejects raw memory feedback payloads" do
    assert {:error, {:raw_memory_payload_forbidden, :body}} =
             Memory.write_feedback(%{body: "raw memory text"})

    assert {:error, {:raw_memory_payload_forbidden, "payload"}} =
             Memory.write_feedback(%{"payload" => "raw payload"})
  end

  test "keeps feedback writes disabled until a product AppKit surface exists" do
    assert {:error, :memory_feedback_write_disabled} =
             Memory.write_feedback(%{
               memory_ref: "memory://fixture/included-project-fact",
               feedback_kind: "helpful"
             })

    assert %{status: :disabled, reason: :dto_only_memory_surface} = Memory.feedback_status()
  end
end
