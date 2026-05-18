defmodule Synapse.ArbitrationTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.ActionResult
  alias Synapse.Arbitration

  test "returns arbitration session positions and consensus posture" do
    assert {:ok, session} = Arbitration.get_session("phase-7")

    assert length(session.positions) == 3
    assert session.quorum.state == :met
    assert session.consensus_posture == :review_required
    assert session.memory_write_status.status == :disabled
  end

  test "routes final decisions through the review surface" do
    assert {:ok, result} =
             Arbitration.record_final_decision("phase-7", %{
               "decision" => "accept",
               "reason" => "Consensus reviewed"
             })

    assert %ActionResult{} = result
    assert result.status == :accepted
  end
end
