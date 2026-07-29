defmodule SynapseWeb.MemoryLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists durable memory projections and context packs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/memory")

    assert has_element?(view, "#memory-index-list")
    assert has_element?(view, "#memory-index-stream", "Included project fact")
    assert has_element?(view, "#memory-index-stream", "episodic")
    assert has_element?(view, "#memory-index-stream", "retention: retained")
    assert has_element?(view, "#memory-index-stream", "degraded")
    assert has_element?(view, "#memory-feedback-status", "disabled")
    assert has_element?(view, "#context-pack-list", "proof-token://synapse/test-snapshot")
  end

  test "shows memory detail and keeps feedback disabled", %{conn: conn} do
    id = URI.encode_www_form("memory://durable/project-fact")
    {:ok, view, _html} = live(conn, "/memory/#{id}")

    assert has_element?(
             view,
             "#memory-projection",
             "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
           )

    assert has_element?(
             view,
             "#memory-provenance",
             "OuterBrain.MemoryContextProvenance.v2"
           )

    assert has_element?(
             view,
             "#memory-projection",
             "artifact://synapse/memory/project-fact"
           )

    assert has_element?(
             view,
             "#memory-retrieval-snapshot",
             "snapshot://synapse/test-snapshot/7"
           )

    assert has_element?(view, "#memory-lifecycle", "retained")
    assert has_element?(view, "#memory-lifecycle", "indexed")
    assert has_element?(view, "#memory-reason-codes")
    assert has_element?(view, "#memory-feedback-form")
    assert has_element?(view, "#memory-feedback-form button[disabled]")

    assert has_element?(
             view,
             "#memory-feedback-disabled",
             "memory_feedback_write_not_in_current_journey"
           )
  end

  test "shows context pack disposition buckets", %{conn: conn} do
    id = URI.encode_www_form("proof-token://synapse/test-snapshot")
    {:ok, view, _html} = live(conn, "/context-packs/#{id}")

    assert has_element?(view, "#context-included-items", "included")
    refute has_element?(view, "#context-denied-items [data-memory-entry]")
    assert has_element?(view, "#context-stale-items", "invalidation_pending")
    assert has_element?(view, "#context-revoked-items", "revoked")
    assert has_element?(view, "#context-candidate-items", "promotion_review_required")
    assert has_element?(view, "#context-degraded-items", "partitioned")
    assert has_element?(view, "#context-memory-manifest", "memory://durable/candidate-learning")
    assert has_element?(view, "#context-memory-manifest", "tombstoned")
    assert has_element?(view, "#context-memory-manifest", "pending")
  end
end
