defmodule Synapse.TurnsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.RuntimeReadback.CommandResult
  alias Synapse.Turns

  test "submits a turn through the injected AppKit backend" do
    assert {:ok, result} =
             Turns.submit_turn("run://durable/test-run", %{
               "kind" => "user_input",
               "input_summary" => "Continue"
             })

    assert %CommandResult{} = result
    assert result.command_kind == :submit_turn
    assert result.accepted? == true
  end

  test "does not fall back when the runtime stack is invalid" do
    assert {:error, :invalid_app_kit_backend_stack} =
             Turns.submit_turn(
               "run://durable/test-run",
               %{"kind" => "user_input", "input_summary" => "Continue"},
               app_kit_backend_stack: nil,
               program_id: "program://test/synapse",
               work_class_id: "work-class://test/agent-run"
             )
  end

  test "routes cancellation through AppKit's dedicated cancellation command" do
    assert {:ok, result} =
             Turns.submit_turn("run://durable/test-run", %{
               "kind" => "cancel",
               "input_summary" => "Stop this reviewed effect"
             })

    assert %CommandResult{} = result
    assert result.command_kind == :cancel
    assert result.accepted? == true
  end

  test "rejects unknown turn kinds without creating atoms" do
    assert {:error, :invalid_turn_kind} =
             Turns.submit_turn("run://durable/test-run", %{"kind" => "unknown_turn_kind"})
  end
end
