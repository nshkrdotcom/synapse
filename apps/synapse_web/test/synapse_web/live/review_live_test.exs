defmodule SynapseWeb.ReviewLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists fixture-backed reviews", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reviews")

    assert has_element?(view, "#review-index-list")
    assert has_element?(view, "#review-index-stream", "Review fixture governed agent run")
    assert has_element?(view, "#review-index-stream", "authority_denied")
  end

  test "shows review detail and records decision", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reviews/fixture-review")

    assert has_element?(view, "#review-decision-form")
    assert has_element?(view, "#review-reason-codes", "review_required")

    view
    |> form("#review-decision-form",
      review: %{decision: "accept", reason: "Fixture reviewed"}
    )
    |> render_submit()

    assert has_element?(view, "#review-decision-result", "accepted")
  end
end
