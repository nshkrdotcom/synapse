defmodule ReviewBotWeb.ReviewLive.New do
  @moduledoc """
  LiveView for creating a new code review.
  """
  use ReviewBotWeb, :live_view

  alias ReviewBot.Reviews
  alias ReviewBot.Reviews.Review
  alias ReviewBot.Workflows.MultiProviderReview

  @impl true
  def mount(_params, _session, socket) do
    changeset = Reviews.change_review(%Review{})

    {:ok,
     socket
     |> assign(:changeset, changeset)
     |> assign(:page_title, "New Review")}
  end

  @impl true
  def handle_event("validate", %{"review" => review_params}, socket) do
    changeset =
      %Review{}
      |> Reviews.change_review(review_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("submit", %{"review" => review_params}, socket) do
    case Reviews.create_review(review_params) do
      {:ok, review} ->
        # Start the workflow asynchronously
        MultiProviderReview.run_async(review)

        {:noreply,
         socket
         |> put_flash(:info, "Review created and started!")
         |> push_navigate(to: ~p"/reviews/#{review.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="header">
        <h1>New Code Review</h1>
        <.link navigate={~p"/"} class="button">
          Back to Reviews
        </.link>
      </div>

      <.form
        for={@changeset}
        phx-change="validate"
        phx-submit="submit"
        class="review-form"
      >
        <div class="form-group">
          <label for="code">Code to Review</label>
          <.input
            field={@changeset[:code]}
            type="textarea"
            placeholder="Paste your code here..."
            rows="15"
            required
          />
        </div>

        <div class="form-group">
          <label for="language">Programming Language (optional)</label>
          <.input
            field={@changeset[:language]}
            type="text"
            placeholder="e.g., elixir, python, javascript"
          />
        </div>

        <div class="form-actions">
          <button type="submit" class="button button-primary" phx-disable-with="Submitting...">
            Submit for Review
          </button>
        </div>

        <div class="info-box">
          <h3>What happens next?</h3>
          <ul>
            <li>Your code will be reviewed by multiple AI providers (Claude, Codex, Gemini)</li>
            <li>Reviews run in parallel for faster results</li>
            <li>You'll see results streaming in real-time</li>
            <li>An aggregated summary will be provided</li>
          </ul>
        </div>
      </.form>
    </div>
    """
  end
end
