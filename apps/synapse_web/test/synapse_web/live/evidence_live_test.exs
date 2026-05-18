defmodule SynapseWeb.EvidenceLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "shows evidence list and replay links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/evidence")

    assert has_element?(view, "#evidence-list", "evidence://synapse/run-start")
    assert has_element?(view, "#evidence-list", "missing")
    assert has_element?(view, "#replay-links", "trace://fixture/replay/phase-8")
  end

  test "shows evidence detail and receipt summary", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/evidence/run-start")

    assert has_element?(view, "#evidence-detail", "run_start")
    assert has_element?(view, "#receipt-summary", "receipt://synapse/run-start")
    assert has_element?(view, "#replay-bundle", "diverged")
  end

  test "renders missing evidence explicitly", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/evidence/missing-live-receipt")

    assert has_element?(view, "#missing-evidence", "live_backend_not_proven")
  end

  test "shows operations health without treating trace export as metrics truth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/operations")

    assert has_element?(view, "#operations-health", "AppKit surfaces")
    assert has_element?(view, "#operations-health", "separate_from_ops_health")
    assert has_element?(view, "#aitrace-separation", "not_used")
    assert has_element?(view, "#runtime-facts", "authorized")
  end
end
