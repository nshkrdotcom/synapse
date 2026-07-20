defmodule Synapse.AgentRunsTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.AgentIntake.AgentRunCursor
  alias AppKit.Core.SurfaceError
  alias Synapse.AgentRuns

  test "starts a run through the injected durable AppKit stack" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Boundary check", "goal_summary" => "Use AppKit only"},
               run_token: "durable-start"
             )

    assert run.ref == "run://durable/durable-start"
    assert run.workflow_ref == "workflow://durable/durable-start"
    assert run.command_ref == "command://durable/start/durable-start"
    assert run.state == :accepted
    assert run.feature_status == :durable_acceptance
  end

  test "returns a typed conflict without constructing accepted product state" do
    assert {:error, %SurfaceError{} = error} =
             AgentRuns.start_run(%{"title" => "Conflict"}, run_token: "conflict")

    assert error.kind == :conflict
    assert error.retryable == false
  end

  test "returns typed transient unavailability" do
    assert {:error, %SurfaceError{} = error} =
             AgentRuns.start_run(%{"title" => "Unavailable"}, run_token: "unavailable")

    assert error.kind == :transient
    assert error.retryable == true
  end

  test "fails closed when an explicit backend stack is invalid" do
    assert {:error, :invalid_app_kit_backend_stack} =
             AgentRuns.start_run(
               %{"title" => "No fallback"},
               app_kit_backend_stack: nil,
               program_id: "program://test/synapse",
               work_class_id: "work-class://test/agent-run",
               run_token: "no-fallback"
             )
  end

  test "lists only rows returned by the durable AppKit snapshot" do
    assert {:ok, [run]} = AgentRuns.list_runs()

    assert run.ref == "run://durable/test-run"
    assert run.state == :accepted
    assert run.title == "Durable run test-run"
    assert run.persistence_posture.durable? == true
  end

  test "loads a durable snapshot and advances its product cursor" do
    assert {:ok, run} = AgentRuns.get_run("run://durable/test-run")

    assert run.feature_status == :durable_snapshot
    assert run.persistence_posture.durable? == true
    assert [%{turn_ref: "turn://durable/test-run/1"}] = run.turns
    assert %AgentRunCursor{} = run.cursor
    assert run.cursor.ledger_ref == "run://durable/test-run"
    assert run.cursor.last_seq_seen == 1
    assert [event] = run.events
    assert event.event_kind == :run_started
  end

  test "refresh resumes from the previously returned durable cursor" do
    assert {:ok, first} = AgentRuns.get_run("run://durable/test-run")
    assert {:ok, refreshed} = AgentRuns.refresh_run(first.ref, cursor: first.cursor)

    assert refreshed.cursor.last_seq_seen == 1
    assert refreshed.cursor.cursor_ref == "cursor://test/test-run/1"
  end

  test "durable projection and cursor readback resume after the product application restarts" do
    assert {:ok, before_restart} = AgentRuns.get_run("run://durable/test-run")

    assert :ok = Application.stop(:synapse_core)

    on_exit(fn ->
      Application.ensure_all_started(:synapse_core)
    end)

    assert {:ok, _started} = Application.ensure_all_started(:synapse_core)

    assert {:ok, after_restart} =
             AgentRuns.refresh_run(before_restart.ref, cursor: before_restart.cursor)

    assert after_restart.ref == before_restart.ref
    assert after_restart.persistence_posture.durable? == true
    assert after_restart.cursor.ledger_ref == before_restart.cursor.ledger_ref
    assert after_restart.cursor.last_seq_seen == before_restart.cursor.last_seq_seen
  end
end
