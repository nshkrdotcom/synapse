defmodule SynapseWeb.CatalogShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Catalog.get_eligibility(id) do
        {:ok, detail} ->
          socket
          |> assign(:page_title, "Catalog Eligibility")
          |> assign(:detail, detail)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Catalog Eligibility")
          |> assign(:detail, nil)
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section
          :if={@detail}
          id="catalog-eligibility-detail"
          class="rounded border border-slate-200 bg-white p-5"
        >
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@detail.item.eligibility_ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@detail.item.title}</h1>
          <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-4">
            <div>
              <dt class="text-slate-500">Status</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.status}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Budget</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.posture.budget}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Quota</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.posture.quota}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Residency</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.posture.residency}</dd>
            </div>
          </dl>
        </section>

        <section
          :if={@detail}
          id="catalog-reason-codes"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Reason Codes</h2>
          <div class="mt-3 flex flex-wrap gap-2 text-xs">
            <span
              :for={reason <- @detail.item.reason_codes}
              class="rounded bg-slate-100 px-2 py-1 text-slate-700"
            >
              {reason}
            </span>
            <span :if={@detail.item.reason_codes == []} class="text-sm text-slate-500">
              none
            </span>
          </div>
        </section>

        <section
          :if={@detail}
          id="catalog-assignment-disabled"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Assignment</h2>
          <p class="mt-2 text-sm text-slate-600">
            {@detail.assignment_status.reason}
          </p>
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
