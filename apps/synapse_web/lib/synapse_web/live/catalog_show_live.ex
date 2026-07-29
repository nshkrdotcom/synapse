defmodule SynapseWeb.CatalogShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Catalog.get_eligibility(id) do
        {:ok, detail} ->
          socket
          |> assign(:page_title, "Catalog Capability")
          |> assign(:detail, detail)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Catalog Capability")
          |> assign(:detail, nil)
          |> assign(:error, error_message(reason))
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
            {@detail.item.ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@detail.item.title}</h1>
          <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-4">
            <div>
              <dt class="text-slate-500">Status</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.status}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Kind</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.kind}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Mode</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.configured_mode}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Contract</dt>
              <dd class="mt-1 font-medium text-slate-950">{@detail.item.contract_version}</dd>
            </div>
          </dl>
        </section>

        <section
          :if={@detail}
          id="catalog-operation-refs"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Executable operations
          </h2>
          <ul class="mt-3 space-y-2 text-sm text-slate-700">
            <li :for={operation_ref <- @detail.item.operation_refs}>{operation_ref}</li>
          </ul>
        </section>

        <section
          :if={@detail && @detail.item.health_ref}
          id="catalog-health-ref"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Health</h2>
          <p class="mt-2 break-words text-sm text-slate-700">{@detail.item.health_ref}</p>
        </section>

        <section
          :if={@error}
          id="catalog-detail-unavailable"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <p class="text-sm font-medium text-amber-800">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp error_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_message(_reason), do: "capability_catalog_unavailable"
end
