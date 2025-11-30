defmodule Synapse.Domains.CodeReviewTest do
  use ExUnit.Case, async: false

  alias Synapse.Domains.CodeReview
  alias Synapse.Signal

  describe "register/0" do
    test "registers all code review signal topics" do
      assert :ok = CodeReview.register()

      assert :review_request in Signal.topics()
      assert :review_result in Signal.topics()
      assert :review_summary in Signal.topics()
      assert :specialist_ready in Signal.topics()
    end

    test "topics have correct wire types" do
      CodeReview.register()

      assert Signal.type(:review_request) == "review.request"
      assert Signal.type(:review_result) == "review.result"
      assert Signal.type(:review_summary) == "review.summary"
    end

    test "can validate review_request payload" do
      CodeReview.register()

      payload = %{review_id: "PR-123", diff: "some diff"}
      result = Signal.validate!(:review_request, payload)

      assert result.review_id == "PR-123"
      assert result.diff == "some diff"
      assert result.files_changed == 0
    end
  end

  describe "topics/0" do
    test "returns list of domain topics" do
      topics = CodeReview.topics()

      assert :review_request in topics
      assert :review_result in topics
      assert :review_summary in topics
      assert :specialist_ready in topics
    end
  end

  describe "actions/0" do
    test "returns list of domain actions" do
      actions = CodeReview.actions()

      assert Synapse.Domains.CodeReview.Actions.ClassifyChange in actions
      assert Synapse.Domains.CodeReview.Actions.CheckSQLInjection in actions
    end
  end
end
