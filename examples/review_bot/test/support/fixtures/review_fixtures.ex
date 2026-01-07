defmodule ReviewBot.ReviewFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ReviewBot.Reviews` context.
  """

  alias ReviewBot.Reviews

  @doc """
  Generate a review.
  """
  def review_fixture(attrs \\ %{}) do
    {:ok, review} =
      attrs
      |> Enum.into(%{
        code: "defmodule Example do\n  def hello, do: :world\nend",
        language: "elixir",
        status: :pending
      })
      |> Reviews.create_review()

    review
  end
end
