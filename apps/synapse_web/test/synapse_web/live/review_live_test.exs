defmodule SynapseWeb.ReviewLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists durable AppKit reviews", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reviews")

    assert has_element?(view, "#review-index-list")
    assert has_element?(view, "#review-index-stream", "Reviewed agent file effect")
    assert has_element?(view, "#review-index-stream", "authority_denied")
  end

  test "shows review detail and records an exact reviewed-effect decision", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reviews/review-unit-1")

    assert has_element?(view, "#review-decision-form")
    assert has_element?(view, "#review-reason-codes", "review_required")

    view
    |> form("#review-decision-form",
      review: %{decision: "accept", reason: "Exact operation reviewed"}
    )
    |> render_submit()

    assert has_element?(view, "#review-decision-result", "completed")
  end

  test "does not fabricate review content when AppKit readback fails", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reviews/missing-review")

    assert has_element?(view, "#review-load-error", "Review unavailable")
    refute has_element?(view, "#review-decision-form")
  end
end
