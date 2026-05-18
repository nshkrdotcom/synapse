defmodule Synapse.AgentRunsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.RuntimeReadback.CommandResult
  alias Synapse.AgentRuns

  test "lists fixture-backed product-safe runs" do
    [run] = AgentRuns.list_runs()

    assert run.ref == "run://fixture/phase-3"
    assert run.surface == "AppKit.AgentIntake"
    assert run.authority_state == :authorized
  end

  test "starts a fixture-backed run through AgentIntake DTOs" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Check the product boundary", "goal_summary" => "Use AppKit only"},
               run_token: "phase-3-test"
             )

    assert run.ref == "run://fixture/phase-3-test"
    assert run.state == :accepted
    assert run.surface == "AppKit.AgentIntake"
  end

  test "refresh and cancel return AppKit command results" do
    assert {:ok, refresh} = AgentRuns.refresh_run("phase-3")
    assert %CommandResult{} = refresh
    assert refresh.command_kind == :refresh
    assert refresh.accepted? == true

    assert {:ok, cancel} = AgentRuns.cancel_run("phase-3")
    assert %CommandResult{} = cancel
    assert cancel.command_kind == :cancel
    assert cancel.accepted? == true
  end
end
