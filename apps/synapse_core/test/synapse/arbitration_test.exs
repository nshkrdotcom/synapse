defmodule Synapse.ArbitrationTest do
  use ExUnit.Case, async: true

  alias Synapse.Arbitration

  test "keeps post-MVP arbitration unavailable" do
    assert %{state: :unavailable, reason: :not_supported} = Arbitration.availability()
    assert [] = Arbitration.list_sessions()
    assert {:error, :arbitration_not_supported} = Arbitration.get_session("phase-7")
  end

  test "does not route an arbitration decision to an unrelated review" do
    assert {:error, :arbitration_not_supported} =
             Arbitration.record_final_decision("phase-7", %{"decision" => "accept"})
  end
end
