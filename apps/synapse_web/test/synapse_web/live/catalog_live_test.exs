defmodule SynapseWeb.CatalogLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "shows tool and model grants", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tool-grant-list", "skill://synapse/document-summary")
    assert has_element?(view, "#tool-grant-list", "effect_write_grant_missing")
    assert has_element?(view, "#model-grant-list", "model-profile://synapse/planner")
    assert has_element?(view, "#catalog-budget-posture", "deny_policy")
  end

  test "shows catalog eligibility list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/catalog")

    assert has_element?(view, "#catalog-eligibility", "Planner model profile")
    assert has_element?(view, "#catalog-eligibility", "External write skill")
    assert has_element?(view, "#catalog-model-list", "model-profile://synapse/summarizer")
    assert has_element?(view, "#catalog-skill-list", "skill://synapse/document-summary")

    assert has_element?(
             view,
             "#catalog-economics-disabled",
             "governed_assignment_surface_not_proven"
           )
  end

  test "shows catalog eligibility detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/catalog/external-write-tool")

    assert has_element?(view, "#catalog-eligibility-detail", "denied")
    assert has_element?(view, "#catalog-reason-codes", "operator_review_required")

    assert has_element?(
             view,
             "#catalog-assignment-disabled",
             "governed_assignment_surface_not_proven"
           )
  end
end
