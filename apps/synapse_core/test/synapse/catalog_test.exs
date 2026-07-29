defmodule Synapse.CatalogTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.ProductSurface.CapabilityProjection
  alias Synapse.Catalog

  test "advertises only executable owner-projected capabilities" do
    catalog = Catalog.catalog()

    assert catalog.status == :available
    assert [%CapabilityProjection{} = capability] = catalog.capabilities
    assert capability.capability_ref == "capability://model/gemini-completion"
    assert catalog.hidden_count == 1

    assert [entry] = catalog.entries
    assert entry.status == :available
    assert entry.operation_refs == ["operation-class://model/completion"]
  end

  test "returns executable eligibility detail from the same projection" do
    id = URI.encode_www_form("capability://model/gemini-completion")
    assert {:ok, detail} = Catalog.get_eligibility(id)

    assert detail.item.status == :available
    assert detail.item.kind == :model
    assert detail.item.health_ref == "health://model/gemini-completion/ready"
    assert detail.item.projection == detail.projection
  end

  test "keeps unsupported assignment absent" do
    assert %{
             status: :unavailable,
             reason: :not_supported
           } = Catalog.assignment_status()
  end

  test "fails closed when the executable product role is absent" do
    stack = Synapse.Test.AppKitBackendStack.backend_stack()
    missing = %{stack | backends: Map.delete(stack.backends, :product_surface_backend)}

    assert %{status: :unavailable, entries: []} =
             Catalog.catalog(app_kit_backend_stack: missing)
  end

  test "rejects raw catalog payloads" do
    assert {:error, {:raw_catalog_payload_forbidden, :secret}} =
             Catalog.reject_raw_payload(%{secret: "token"})

    assert {:error, {:raw_catalog_payload_forbidden, "provider_payload"}} =
             Catalog.reject_raw_payload(%{"provider_payload" => %{}})
  end
end
