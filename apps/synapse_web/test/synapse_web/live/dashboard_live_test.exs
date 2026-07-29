defmodule SynapseWeb.DashboardLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "renders durable run summaries without fixture operational truth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#dashboard-health")

    assert has_element?(
             view,
             "#dashboard-product-health-state[data-state=available]",
             "available"
           )

    assert has_element?(view, "#dashboard-active-runs")
    assert has_element?(view, "#dashboard-run-rows", "run://durable/test-run")
    assert has_element?(view, "#dashboard-run-readback", "durable")
    assert has_element?(view, "#dashboard-review-status", "2 pending")
    assert has_element?(view, "#dashboard-operations-status", "available")
    assert has_element?(view, "#dashboard-capability-health[data-state=available]")
    assert has_element?(view, "#dashboard-advertised-capability-count", "1")
    assert has_element?(view, "#dashboard-hidden-capability-count", "1")
    refute has_element?(view, "#dashboard-run-readback-unavailable")
  end
end
