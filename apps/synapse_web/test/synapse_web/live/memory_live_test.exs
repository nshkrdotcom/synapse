defmodule SynapseWeb.MemoryLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists fixture-backed memory projections and context packs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/memory")

    assert has_element?(view, "#memory-index-list")
    assert has_element?(view, "#memory-index-stream", "Included project fact")
    assert has_element?(view, "#memory-index-stream", "denied")
    assert has_element?(view, "#memory-feedback-status", "disabled")
    assert has_element?(view, "#context-pack-list", "context-pack://fixture/phase-3")
  end

  test "shows memory detail and keeps feedback disabled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/memory/included-project-fact")

    assert has_element?(view, "#memory-projection", "sha256:included-project-fact")
    assert has_element?(view, "#memory-reason-codes")
    assert has_element?(view, "#memory-feedback-form")

    view
    |> form("#memory-feedback-form",
      feedback: %{memory_ref: "memory://fixture/included-project-fact"}
    )
    |> render_submit()

    assert has_element?(view, "#memory-feedback-disabled", "dto_only_memory_surface")
  end

  test "shows context pack disposition buckets", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/context-packs/phase-3")

    assert has_element?(view, "#context-included-items", "included")
    assert has_element?(view, "#context-denied-items", "authority_denied")
    assert has_element?(view, "#context-stale-items", "superseded")
    assert has_element?(view, "#context-revoked-items", "revoked")
    assert has_element?(view, "#context-candidate-items", "promotion_review_required")
  end
end
