defmodule ReviewBot.ReviewsTest do
  use ReviewBot.DataCase

  alias ReviewBot.Reviews

  describe "reviews" do
    alias ReviewBot.Reviews.Review

    import ReviewBot.ReviewFixtures

    @invalid_attrs %{code: nil, language: nil, status: nil}

    test "list_reviews/0 returns all reviews" do
      review = review_fixture()
      assert Reviews.list_reviews() == [review]
    end

    test "get_review!/1 returns the review with given id" do
      review = review_fixture()
      assert Reviews.get_review!(review.id) == review
    end

    test "create_review/1 with valid data creates a review" do
      valid_attrs = %{code: "def hello, do: :world", language: "elixir"}

      assert {:ok, %Review{} = review} = Reviews.create_review(valid_attrs)
      assert review.code == "def hello, do: :world"
      assert review.language == "elixir"
      assert review.status == :pending
      assert is_binary(review.workflow_id)
    end

    test "create_review/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Reviews.create_review(@invalid_attrs)
    end

    test "update_review/2 with valid data updates the review" do
      review = review_fixture()
      update_attrs = %{status: :completed, results: %{"test" => "data"}}

      assert {:ok, %Review{} = review} = Reviews.update_review(review, update_attrs)
      assert review.status == :completed
      assert review.results == %{"test" => "data"}
    end

    test "update_review_status/2 updates the review status" do
      review = review_fixture()
      assert {:ok, %Review{} = updated} = Reviews.update_review_status(review, :in_progress)
      assert updated.status == :in_progress
    end

    test "delete_review/1 deletes the review" do
      review = review_fixture()
      assert {:ok, %Review{}} = Reviews.delete_review(review)
      assert_raise Ecto.NoResultsError, fn -> Reviews.get_review!(review.id) end
    end

    test "change_review/1 returns a review changeset" do
      review = review_fixture()
      assert %Ecto.Changeset{} = Reviews.change_review(review)
    end
  end
end
