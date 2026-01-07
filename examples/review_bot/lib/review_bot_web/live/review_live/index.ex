defmodule ReviewBotWeb.ReviewLive.Index do
  @moduledoc """
  LiveView for listing all code reviews.
  """
  use ReviewBotWeb, :live_view

  alias ReviewBot.Reviews

  @impl true
  def mount(_params, _session, socket) do
    reviews = Reviews.list_reviews()
    {:ok, assign(socket, reviews: reviews, filter: :all)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Code Reviews")
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filter = String.to_existing_atom(status)

    reviews =
      case filter do
        :all -> Reviews.list_reviews()
        status -> Reviews.list_reviews_by_status(status)
      end

    {:noreply, assign(socket, reviews: reviews, filter: filter)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="header">
        <h1>Code Reviews</h1>
        <.link navigate={~p"/reviews/new"} class="button button-primary">
          New Review
        </.link>
      </div>

      <div class="filters">
        <button
          phx-click="filter"
          phx-value-status="all"
          class={"filter-btn #{if @filter == :all, do: "active"}"}
        >
          All
        </button>
        <button
          phx-click="filter"
          phx-value-status="pending"
          class={"filter-btn #{if @filter == :pending, do: "active"}"}
        >
          Pending
        </button>
        <button
          phx-click="filter"
          phx-value-status="in_progress"
          class={"filter-btn #{if @filter == :in_progress, do: "active"}"}
        >
          In Progress
        </button>
        <button
          phx-click="filter"
          phx-value-status="completed"
          class={"filter-btn #{if @filter == :completed, do: "active"}"}
        >
          Completed
        </button>
        <button
          phx-click="filter"
          phx-value-status="failed"
          class={"filter-btn #{if @filter == :failed, do: "active"}"}
        >
          Failed
        </button>
      </div>

      <div class="reviews-list">
        <%= if Enum.empty?(@reviews) do %>
          <div class="empty-state">
            <p>No reviews found.</p>
            <.link navigate={~p"/reviews/new"} class="button button-primary">
              Create Your First Review
            </.link>
          </div>
        <% else %>
          <%= for review <- @reviews do %>
            <.link navigate={~p"/reviews/#{review.id}"} class="review-card">
              <div class="review-card-header">
                <span class={"status-badge status-#{review.status}"}>
                  <%= review.status %>
                </span>
                <span class="review-date">
                  <%= Calendar.strftime(review.inserted_at, "%Y-%m-%d %H:%M") %>
                </span>
              </div>
              <div class="review-card-body">
                <code class="review-preview">
                  <%= String.slice(review.code, 0..100) %><%= if String.length(review.code) > 100,
                    do: "..." %>
                </code>
                <%= if review.language do %>
                  <span class="language-tag"><%= review.language %></span>
                <% end %>
              </div>
            </.link>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
