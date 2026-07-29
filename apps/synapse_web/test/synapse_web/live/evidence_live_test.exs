defmodule SynapseWeb.EvidenceLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "shows durable owner evidence and artifacts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/evidence")

    assert has_element?(view, "#evidence-list", "evidence://synapse/test-run/output")
    assert has_element?(view, "#evidence-list", "evidence://synapse/test-run/model/1")
    assert has_element?(view, "#artifact-list", "artifact://synapse/turn/test-run/1/output")
  end

  test "shows operation evidence detail and exact receipt", %{conn: conn} do
    id = URI.encode_www_form("evidence://synapse/test-run/model/1")
    {:ok, view, _html} = live(conn, "/evidence/#{id}")

    assert has_element?(view, "#evidence-detail", "operation_evidence")
    assert has_element?(view, "#receipt-summary", "receipt://synapse/test-run/model/1")
    assert has_element?(view, "#evidence-lineage", "operation://synapse/test-run/model/1")
  end

  test "shows operations health without treating trace export as metrics truth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/operations")

    assert has_element?(view, "#operations-health", "app kit surfaces")
    assert has_element?(view, "#operations-health", "separate_from_ops_health")
    assert has_element?(view, "#operation-list", "operation://synapse/test-run/model/1")
    assert has_element?(view, "#runtime-facts", "separate_from_operations_health")
  end
end
