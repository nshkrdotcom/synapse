defmodule Synapse.TeamsTest do
  use ExUnit.Case, async: true

  alias AppKit.CoordinationSurface.{CoordinationProjection, RunControlRequest}
  alias AppKit.HiveSurface.HiveProjection
  alias Synapse.Teams

  test "lists fixture-backed team projections" do
    assert [team] = Teams.list_teams()

    assert team.feature_status == :fixture_backed
    assert team.executable_surface == :dto_only
    assert %CoordinationProjection{} = team.coordination_projection
    assert %HiveProjection{} = team.hive_projection
  end

  test "returns team detail with members, quorum, and memory grants" do
    assert {:ok, team} = Teams.get_team("fixture-team")

    assert length(team.members) == 3
    assert team.join_barrier.quorum_state == :met
    assert Enum.any?(team.memory_grants, &(&1.status == :denied))
  end

  test "builds but does not execute DTO-only control requests" do
    assert {:ok, request} = Teams.request_control("fixture-team", %{"control_class" => "cancel"})

    assert %RunControlRequest{} = request
    assert request.control_class == :cancel
    assert request.execution_status == :disabled
  end
end
