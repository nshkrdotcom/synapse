defmodule ReviewBotWeb.ReviewLiveTest do
  use ReviewBotWeb.ConnCase

  import Phoenix.LiveViewTest
  import ReviewBot.ReviewFixtures

  describe "Index" do
    test "lists all reviews", %{conn: conn} do
      review = review_fixture()
      {:ok, _index_live, html} = live(conn, ~p"/")

      assert html =~ "Code Reviews"
      assert html =~ String.slice(review.code, 0..50)
    end

    test "filters reviews by status", %{conn: conn} do
      _pending_review = review_fixture(%{status: :pending})
      completed_review = review_fixture(%{status: :completed})

      {:ok, index_live, _html} = live(conn, ~p"/")

      # Filter by completed
      html =
        index_live
        |> element("button", "Completed")
        |> render_click()

      assert html =~ String.slice(completed_review.code, 0..50)
    end
  end

  describe "New" do
    test "saves new review and redirects to show", %{conn: conn} do
      {:ok, new_live, _html} = live(conn, ~p"/reviews/new")

      assert new_live
             |> form("#review-form", review: %{code: "def test, do: :ok", language: "elixir"})
             |> render_submit()

      # Should redirect to show page
      assert_redirected(new_live, ~p"/reviews/#{1}")
    end

    test "validates required fields", %{conn: conn} do
      {:ok, new_live, _html} = live(conn, ~p"/reviews/new")

      assert new_live
             |> form("#review-form", review: %{code: ""})
             |> render_change() =~ "can&#39;t be blank"
    end
  end

  describe "Show" do
    test "displays review", %{conn: conn} do
      review = review_fixture()
      {:ok, _show_live, html} = live(conn, ~p"/reviews/#{review.id}")

      assert html =~ "Code Review"
      assert html =~ review.code
    end

    test "displays language tag when present", %{conn: conn} do
      review = review_fixture(%{language: "elixir"})
      {:ok, _show_live, html} = live(conn, ~p"/reviews/#{review.id}")

      assert html =~ "elixir"
    end
  end
end
