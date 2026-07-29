defmodule Synapse.ProductProfileTest do
  use ExUnit.Case, async: true

  alias Synapse.ProductProfile

  test "declares AppKit requirements without static runtime availability claims" do
    posture = ProductProfile.feature_status()

    assert posture.runs == :app_kit_owner_projected
    assert posture.turns == :app_kit_owner_projected
    assert posture.controls == :app_kit_owner_projected
    assert posture.operations == :app_kit_owner_projected
    assert posture.tools == :not_routed
    assert posture.teams == :not_routed
    assert posture.arbitration == :not_routed

    refute :fixture_backed in Map.values(posture)
    refute :live in Map.values(posture)

    assert Enum.all?(
             ProductProfile.team_templates(),
             &(&1.execution_posture == :configuration_only)
           )
  end
end
