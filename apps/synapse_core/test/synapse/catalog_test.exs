defmodule Synapse.CatalogTest do
  use ExUnit.Case, async: true

  alias AppKit.ModelSurface.CatalogProjection
  alias AppKit.SkillSurface.SkillProjection
  alias Synapse.Catalog

  test "builds fixture-backed model and skill catalog projections" do
    catalog = Catalog.catalog()

    assert catalog.status == :fixture_backed
    assert %CatalogProjection{} = catalog.model_catalog
    assert Enum.all?(catalog.skills, &match?(%SkillProjection{}, &1))
    assert length(catalog.tool_grants) == 2
    assert Enum.any?(catalog.tool_grants, &(&1.status == :denied))
  end

  test "returns eligibility detail with budget and cost posture" do
    assert {:ok, detail} = Catalog.get_eligibility("external-write-tool")

    assert detail.item.status == :denied
    assert "effect_write_grant_missing" in detail.item.reason_codes
    assert detail.budgets.denied_effect_budget.decision_class == :deny_policy
    assert detail.costs.redaction_posture == "bounded_amount_classes_only"
  end

  test "keeps governed assignment disabled until the platform surface is proven" do
    assert %{
             status: :disabled,
             reason: :governed_assignment_surface_not_proven
           } = Catalog.assignment_status()
  end

  test "rejects raw catalog payloads" do
    assert {:error, {:raw_catalog_payload_forbidden, :secret}} =
             Catalog.reject_raw_payload(%{secret: "token"})

    assert {:error, {:raw_catalog_payload_forbidden, "provider_payload"}} =
             Catalog.reject_raw_payload(%{"provider_payload" => %{}})
  end
end
