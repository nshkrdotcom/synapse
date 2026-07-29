defmodule Synapse.ReviewsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.ActionResult
  alias Synapse.Reviews

  test "lists durable reviews through the configured AppKit review backend" do
    assert {:ok, page} = Reviews.list_pending()

    assert page.total_count == 2
    assert page.source == :durable_test_backend
    assert Enum.any?(page.entries, &(&1.id == "review-unit-1"))
    assert Enum.any?(page.entries, &(&1.denied? == true))
  end

  test "returns AppKit review detail with exact effect approval data" do
    assert {:ok, review} = Reviews.get_review("review-unit-1")

    assert review.decision_id == "review-unit-1"
    assert "review_required" in review.reason_codes
    assert review.approval_payload["reviewed_operation"]["relative_path"] == "RESULT.txt"
  end

  test "binds an allowed decision to the exact owner-projected effect through AppKit" do
    payload = %{
      "effect_ref" => "effect://test/reviewed-file",
      "pinned_tool_manifest" => %{"manifest_ref" => "manifest://test/codex"},
      "reviewed_operation" => %{"relative_path" => "RESULT.txt"}
    }

    assert {:ok, result} =
             Reviews.record_decision("review-unit-1", %{
               "decision" => "accept",
               "reason" => "Looks correct",
               "payload" => payload
             })

    assert %ActionResult{} = result
    assert result.status == :completed
    assert result.metadata.decision == :accept
    assert result.metadata.payload["effect_ref"] == payload["effect_ref"]

    assert result.metadata.payload["pinned_tool_manifest"]["manifest_hash"] ==
             "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    assert result.metadata.payload["reviewed_operation"]["content_digest"] ==
             "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  test "rejects unknown decision without creating atoms" do
    assert {:error, :invalid_review_decision} =
             Reviews.record_decision("review-unit-1", %{"decision" => "ship_it"})
  end
end
