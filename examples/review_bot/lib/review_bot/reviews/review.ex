defmodule ReviewBot.Reviews.Review do
  @moduledoc """
  Schema for code reviews.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "reviews" do
    field(:code, :string)
    field(:language, :string)
    field(:status, Ecto.Enum, values: [:pending, :in_progress, :completed, :failed])
    field(:results, :map)
    field(:workflow_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(review, attrs) do
    review
    |> cast(attrs, [:code, :language, :status, :results, :workflow_id])
    |> validate_required([:code, :status])
    |> validate_length(:code, min: 1, max: 100_000)
  end

  @doc """
  Changeset for creating a new review.
  """
  def create_changeset(review, attrs) do
    review
    |> cast(attrs, [:code, :language])
    |> validate_required([:code])
    |> validate_length(:code, min: 1, max: 100_000)
    |> put_change(:status, :pending)
    |> put_change(:results, %{})
    |> put_workflow_id()
  end

  defp put_workflow_id(changeset) do
    case get_change(changeset, :workflow_id) do
      nil -> put_change(changeset, :workflow_id, generate_workflow_id())
      _id -> changeset
    end
  end

  defp generate_workflow_id do
    "review_#{System.system_time(:millisecond)}_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
