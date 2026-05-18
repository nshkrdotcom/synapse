defmodule Synapse.ProductPackTest do
  use ExUnit.Case, async: true

  alias Mezzanine.Pack.Manifest
  alias Synapse.{DefaultAuthoringBundle, ProductPack, ProductProfile}

  test "builds the neutral NSHKR Agent manifest" do
    manifest = ProductPack.manifest()

    assert %Manifest{} = manifest
    assert manifest.pack_slug == "nshkr-agent"
    assert manifest.version == "0.1.0"

    assert Enum.map(ProductProfile.roles(), & &1.ref) == [
             :coordinator,
             :research_specialist,
             :implementation_specialist,
             :security_specialist,
             :performance_specialist,
             :documentation_specialist,
             :review_synthesizer,
             :arbitration_chair
           ]

    assert Enum.any?(
             manifest.operation_graph_specs,
             &(&1.graph_ref == :synapse_agent_operation_graph)
           )

    assert Enum.any?(manifest.decision_specs, &(&1.decision_kind == :operator_review))
  end

  test "authoring bundle payload does not bake vendor provider names" do
    {:ok, bundle} = DefaultAuthoringBundle.build([])
    payload = inspect(bundle.pack_manifest)

    forbidden_vendor_names = [
      "git" <> "hub",
      "lin" <> "ear",
      "co" <> "dex",
      "open" <> "ai",
      "cla" <> "ude",
      "gem" <> "ini"
    ]

    for vendor <- forbidden_vendor_names do
      refute String.contains?(payload, vendor)
    end
  end
end
