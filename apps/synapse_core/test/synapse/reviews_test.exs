defmodule Synapse.ReviewsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.ActionResult
  alias Synapse.Reviews

  test "lists fixture-backed pending reviews" do
    assert {:ok, page} = Reviews.list_pending()

    assert page.total_count == 2
    assert Enum.any?(page.entries, &(&1.id == "fixture-review"))
    assert Enum.any?(page.entries, &(&1.denied? == true))
  end

  test "returns review detail with reason codes" do
    assert {:ok, review} = Reviews.get_review("fixture-review")

    assert review.decision_id == "decision://fixture/fixture-review"
    assert "review_required" in review.reason_codes
  end

  test "records an allowed fixture review decision" do
    assert {:ok, result} =
             Reviews.record_decision("fixture-review", %{
               "decision" => "accept",
               "reason" => "Looks correct"
             })

    assert %ActionResult{} = result
    assert result.status == :accepted
    assert result.metadata.decision == :accept
  end

  test "rejects unknown decision without creating atoms" do
    assert {:error, :invalid_review_decision} =
             Reviews.record_decision("fixture-review", %{"decision" => "ship_it"})
  end
end
