defmodule ReviewBotWeb.ReviewLive.Show do
  @moduledoc """
  LiveView for showing a code review with real-time streaming results.
  """
  use ReviewBotWeb, :live_view

  alias ReviewBot.Reviews
  alias ReviewBot.Workflows.MultiProviderReview

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    review = Reviews.get_review!(id)

    socket =
      socket
      |> assign(:review, review)
      |> assign(:provider_results, %{})
      |> assign(:page_title, "Review ##{review.id}")

    # Subscribe to PubSub for real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReviewBot.PubSub, "review:#{id}")
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:provider_result, provider, result}, socket) do
    provider_results = Map.put(socket.assigns.provider_results, provider, result)
    {:noreply, assign(socket, provider_results: provider_results)}
  end

  @impl true
  def handle_info({:review_complete, final_result}, socket) do
    review = %{socket.assigns.review | status: :completed, results: final_result}
    {:noreply, assign(socket, review: review)}
  end

  @impl true
  def handle_info({:review_failed, _failure}, socket) do
    review = %{socket.assigns.review | status: :failed}
    {:noreply, assign(socket, review: review)}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    review = socket.assigns.review
    MultiProviderReview.run_async(review)

    {:noreply,
     socket
     |> assign(:provider_results, %{})
     |> put_flash(:info, "Review restarted")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="header">
        <h1>Code Review #<%= @review.id %></h1>
        <div class="header-actions">
          <span class={"status-badge status-#{@review.status}"}>
            <%= @review.status %>
          </span>
          <%= if @review.status == :failed do %>
            <button phx-click="retry" class="button">
              Retry Review
            </button>
          <% end %>
          <.link navigate={~p"/"} class="button">
            Back to Reviews
          </.link>
        </div>
      </div>

      <div class="review-content">
        <div class="code-section">
          <h2>Code Under Review</h2>
          <%= if @review.language do %>
            <span class="language-tag"><%= @review.language %></span>
          <% end %>
          <pre><code><%= @review.code %></code></pre>
        </div>

        <div class="results-section">
          <h2>Review Results</h2>

          <%= if @review.status == :pending or @review.status == :in_progress do %>
            <div class="loading-state">
              <div class="spinner"></div>
              <p>Analyzing code with multiple AI providers...</p>
            </div>
          <% end %>

          <div class="provider-results">
            <%= for provider <- [:claude, :codex, :gemini] do %>
              <.provider_result_card
                provider={provider}
                result={Map.get(@provider_results, provider)}
              />
            <% end %>
          </div>

          <%= if @review.status == :completed and @review.results do %>
            <div class="aggregated-results">
              <h2>Aggregated Analysis</h2>

              <%= if combined = @review.results["combined"] do %>
                <div class="summary-card">
                  <div class="score-section">
                    <h3>Overall Quality Score</h3>
                    <div class="score-display">
                      <%= combined["average_score"] %><span class="score-max">/100</span>
                    </div>
                  </div>

                  <div class="stats-grid">
                    <div class="stat">
                      <span class="stat-label">Providers</span>
                      <span class="stat-value"><%= combined["provider_count"] %></span>
                    </div>
                    <div class="stat">
                      <span class="stat-label">Total Issues</span>
                      <span class="stat-value"><%= combined["total_issues"] %></span>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if summary = @review.results["summary"] do %>
                <div class="summary-text">
                  <h3>Summary</h3>
                  <p><%= summary %></p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp provider_result_card(assigns) do
    ~H"""
    <div class="provider-card">
      <div class="provider-header">
        <h3><%= format_provider_name(@provider) %></h3>
        <%= if @result do %>
          <span class="status-badge status-completed">Completed</span>
        <% else %>
          <span class="status-badge status-pending">Pending...</span>
        <% end %>
      </div>

      <%= if @result do %>
        <div class="provider-content">
          <%= if analysis = @result[:analysis] || @result["analysis"] do %>
            <div class="quality-score">
              Score: <strong><%= analysis[:quality_score] || analysis["quality_score"] %>/100</strong>
            </div>

            <%= if summary = analysis[:summary] || analysis["summary"] do %>
              <p class="provider-summary"><%= summary %></p>
            <% end %>

            <%= if issues = analysis[:issues] || analysis["issues"] do %>
              <div class="issues-list">
                <h4>Issues Found (<%= length(issues) %>)</h4>
                <%= for issue <- issues do %>
                  <div class={"issue-item severity-#{issue[:severity] || issue["severity"]}"}>
                    <span class="issue-type"><%= issue[:type] || issue["type"] %></span>
                    <%= if line = issue[:line] || issue["line"] do %>
                      <span class="issue-line">Line <%= line %></span>
                    <% end %>
                    <p class="issue-message"><%= issue[:message] || issue["message"] %></p>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <div class="provider-loading">
          <div class="spinner-sm"></div>
          <span>Analyzing...</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_provider_name(:claude), do: "Claude AI"
  defp format_provider_name(:codex), do: "OpenAI Codex"
  defp format_provider_name(:gemini), do: "Google Gemini"
  defp format_provider_name(provider), do: provider |> to_string() |> String.capitalize()
end
