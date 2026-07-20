defmodule SynapseWeb.DashboardLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "renders durable run summaries without fixture operational truth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#dashboard-health")
    assert has_element?(view, "#dashboard-active-runs")
    assert has_element?(view, "#dashboard-run-rows", "run://durable/test-run")
    assert has_element?(view, "#dashboard-run-readback", "durable")
    assert has_element?(view, "#dashboard-review-status", "Not activated")
    assert has_element?(view, "#dashboard-operations-status", "No local operational truth")
    refute has_element?(view, "#dashboard-run-readback-unavailable")
  end
end
