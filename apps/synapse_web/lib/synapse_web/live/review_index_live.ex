defmodule SynapseWeb.ReviewIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, page} = Synapse.Reviews.list_pending()

    socket =
      socket
      |> assign(:page_title, "Reviews")
      |> assign(:total_count, page.total_count)
      |> stream(:reviews, page.entries)

    {:ok, socket}
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
          id="review-index-list"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <div class="border-b border-slate-200 px-4 py-3 text-sm text-slate-600">
            {@total_count} review entries
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
        </section>
      </div>
    </Layouts.app>
    """
  end
end
