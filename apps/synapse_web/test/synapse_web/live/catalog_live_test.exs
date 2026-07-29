defmodule SynapseWeb.CatalogLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "shows only executable catalog entries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/catalog")

    assert has_element?(
             view,
             "#catalog-eligibility",
             "capability://model/gemini-completion"
           )

    refute has_element?(view, "#catalog-eligibility", "capability://execution/runtime-http")
  end

  test "shows catalog eligibility detail", %{conn: conn} do
    id = URI.encode_www_form("capability://model/gemini-completion")
    {:ok, view, _html} = live(conn, "/catalog/#{id}")

    assert has_element?(view, "#catalog-eligibility-detail", "available")
    assert has_element?(view, "#catalog-operation-refs", "operation-class://model/completion")
    assert has_element?(view, "#catalog-health-ref", "health://model/gemini-completion/ready")
  end
end
