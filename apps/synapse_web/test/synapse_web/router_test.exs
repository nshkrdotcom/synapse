defmodule SynapseWeb.RouterTest do
  use ExUnit.Case, async: true

  test "does not route incomplete tool, team, or arbitration screens" do
    paths = SynapseWeb.Router.__routes__() |> Enum.map(& &1.path)

    refute "/tools" in paths
    refute "/teams" in paths
    refute "/teams/:id" in paths
    refute "/arbitration/:id" in paths
  end
end
