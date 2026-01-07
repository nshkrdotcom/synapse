defmodule ReviewBot.Reviews do
  @moduledoc """
  The Reviews context.
  """

  import Ecto.Query, warn: false
  alias ReviewBot.Repo
  alias ReviewBot.Reviews.Review

  @doc """
  Returns the list of reviews.
  """
  def list_reviews do
    Review
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns reviews filtered by status.
  """
  def list_reviews_by_status(status) do
    Review
    |> where([r], r.status == ^status)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single review.
  Raises `Ecto.NoResultsError` if the Review does not exist.
  """
  def get_review!(id), do: Repo.get!(Review, id)

  @doc """
  Gets a review by workflow_id.
  """
  def get_review_by_workflow_id(workflow_id) do
    Repo.get_by(Review, workflow_id: workflow_id)
  end

  @doc """
  Creates a review.
  """
  def create_review(attrs \\ %{}) do
    %Review{}
    |> Review.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a review.
  """
  def update_review(%Review{} = review, attrs) do
    review
    |> Review.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a review's status.
  """
  def update_review_status(%Review{} = review, status) do
    update_review(review, %{status: status})
  end

  @doc """
  Updates a review's results.
  """
  def update_review_results(%Review{} = review, results) do
    update_review(review, %{results: results})
  end

  @doc """
  Deletes a review.
  """
  def delete_review(%Review{} = review) do
    Repo.delete(review)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking review changes.
  """
  def change_review(%Review{} = review, attrs \\ %{}) do
    Review.changeset(review, attrs)
  end
end
