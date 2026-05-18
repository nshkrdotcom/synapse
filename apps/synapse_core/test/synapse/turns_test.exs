defmodule Synapse.TurnsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.RuntimeReadback.CommandResult
  alias Synapse.Turns

  test "submits a fixture-backed turn through AgentIntake DTOs" do
    assert {:ok, result} =
             Turns.submit_turn("phase-3", %{
               "kind" => "user_input",
               "input_summary" => "Continue"
             })

    assert %CommandResult{} = result
    assert result.command_kind == :submit_turn
    assert result.accepted? == true
  end

  test "rejects unknown turn kinds without creating atoms" do
    assert {:error, :invalid_turn_kind} =
             Turns.submit_turn("phase-3", %{"kind" => "unknown_turn_kind"})
  end
end
