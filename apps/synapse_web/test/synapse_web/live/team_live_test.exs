defmodule SynapseWeb.TeamLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists fixture-backed team projections", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teams")

    assert has_element?(view, "#team-index-list", "Fixture implementation team")
    assert has_element?(view, "#team-index-list", "dto_only")
  end

  test "shows team detail state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teams/fixture-team")

    assert has_element?(view, "#team-member-state", "role://synapse/planner")
    assert has_element?(view, "#team-join-barrier", "waiting_for_reviewer")
    assert has_element?(view, "#team-quorum-state", "met")
    assert has_element?(view, "#team-fanout-fanin", "awaiting_consensus")
    assert has_element?(view, "#team-hive-projection", "hive-projection://synapse/team/phase-7")
  end

  test "shows arbitration detail and records review-routed decision", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/arbitration/phase-7")

    assert has_element?(view, "#arbitration-positions", "needs_review")
    assert has_element?(view, "#arbitration-consensus", "met")
    assert has_element?(view, "#arbitration-memory-grants", "memory_write_grant_required")
    assert has_element?(view, "#arbitration-decision-form")

    view
    |> form("#arbitration-decision-form",
      decision: %{decision: "accept", reason: "Consensus reviewed"}
    )
    |> render_submit()

    assert has_element?(view, "#arbitration-decision-result", "accepted")
  end
end
