defmodule SynapseWeb.ReviewIndexLive do
  use SynapseWeb, :live_view

  alias AppKit.Core.SurfaceError

  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Reviews")
      |> assign(:total_count, 0)
      |> assign(:has_more, false)
      |> assign(:source, nil)
      |> assign(:readback_state, :loading)
      |> assign(:readback_error, nil)
      |> assign(:loaded_once?, false)
      |> stream(:reviews, [], dom_id: &review_dom_id/1)
      |> load_reviews()

    if connected?(socket), do: schedule_refresh()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_reviews, socket) do
    schedule_refresh()
    {:noreply, load_reviews(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Reviews</h1>
          <p class="mt-1 text-sm text-slate-600">
            Durable review queue projected and decided through AppKit.
          </p>
        </section>

        <section
          :if={@readback_state in [:unavailable, :degraded]}
          id="review-index-readback-state"
          data-state={@readback_state}
          class="rounded border border-amber-300 bg-amber-50 p-4 text-amber-950"
        >
          <h2 class="font-semibold">
            {if @readback_state == :degraded,
              do: "Review readback is temporarily degraded",
              else: "Reviews are unavailable"}
          </h2>
          <p class="mt-1 text-sm">{@readback_error}</p>
          <p :if={@readback_state == :degraded} class="mt-1 text-xs">
            The rows below are the last durable AppKit projection received by this view.
          </p>
        </section>

        <section
          id="review-index-list"
          data-readback-state={@readback_state}
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <div class="border-b border-slate-200 px-4 py-3 text-sm text-slate-600">
            {@total_count} review entries <span :if={@has_more}> · more entries are available</span>
          </div>

          <div id="review-index-stream" phx-update="stream" class="divide-y divide-slate-100">
            <div :for={{dom_id, review} <- @streams.reviews} id={dom_id} class="p-4">
              <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                <div>
                  <.link
                    navigate={~p"/reviews/#{review.id}"}
                    class="font-semibold text-slate-950 hover:underline"
                  >
                    {review.title}
                  </.link>
                  <div class="mt-1 text-xs text-slate-500">{review.decision_id}</div>
                </div>
                <div class="flex flex-wrap gap-2 text-xs">
                  <span class="rounded border border-slate-200 px-2 py-1 text-slate-700">
                    {review.status}
                  </span>
                  <span class="rounded border border-slate-200 px-2 py-1 text-slate-700">
                    {review.authority_state}
                  </span>
                </div>
              </div>

              <div class="mt-3 flex flex-wrap gap-2 text-xs text-slate-500">
                <span :for={reason <- review.reason_codes} class="rounded bg-slate-100 px-2 py-1">
                  {reason}
                </span>
              </div>
            </div>
          </div>

          <p
            :if={@loaded_once? && @total_count == 0}
            id="review-index-empty"
            class="px-4 py-8 text-center text-sm text-slate-600"
          >
            AppKit returned no pending reviews.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp load_reviews(socket) do
    case Synapse.Reviews.list_pending() do
      {:ok, page} ->
        socket
        |> assign(:total_count, page.total_count)
        |> assign(:has_more, page.has_more)
        |> assign(:source, page.source)
        |> assign(:readback_state, :available)
        |> assign(:readback_error, nil)
        |> assign(:loaded_once?, true)
        |> stream(:reviews, page.entries, reset: true)

      {:error, reason} ->
        state = if socket.assigns.loaded_once?, do: :degraded, else: :unavailable

        socket
        |> assign(:readback_state, state)
        |> assign(:readback_error, error_message(reason))
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_reviews, @refresh_interval_ms)
  end

  defp review_dom_id(review), do: "review-row-" <> stable_dom_token(review.id)

  defp stable_dom_token(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp error_message(%SurfaceError{message: message}), do: message

  defp error_message(reason)
       when reason in [
              :app_kit_backend_unavailable,
              :invalid_durable_review_page,
              :invalid_durable_review_projection,
              :invalid_durable_review_status
            ],
       do: "AppKit did not return a complete durable review projection."

  defp error_message(_reason), do: "The durable review queue could not be read through AppKit."
end
