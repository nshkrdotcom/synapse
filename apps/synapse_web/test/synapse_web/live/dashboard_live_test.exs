defmodule SynapseWeb.DashboardLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "renders the operational dashboard shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#dashboard-health")
    assert has_element?(view, "#dashboard-active-runs")
    assert has_element?(view, "#dashboard-pending-reviews")
    assert has_element?(view, "#dashboard-denials")
    assert has_element?(view, "#installation-bootstrap-status")
    assert has_element?(view, "#operations-slo-list")
  end
end
