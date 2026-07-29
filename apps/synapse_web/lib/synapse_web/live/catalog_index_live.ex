defmodule SynapseWeb.CatalogIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    catalog = Synapse.Catalog.catalog()

    socket =
      socket
      |> assign(:page_title, "Catalog")
      |> assign(:catalog, catalog)
      |> stream(:entries, catalog.entries)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Catalog</h1>
          <p class="mt-1 text-sm text-slate-600">
            Executable capabilities admitted by the composed AppKit runtime.
          </p>
        </section>

        <section
          :if={@catalog.status == :unavailable}
          id="catalog-unavailable"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-900">
            Catalog unavailable
          </h2>
          <p id="catalog-unavailable-reason" class="mt-2 text-sm text-amber-800">
            {availability_reason(@catalog.availability)}
          </p>
        </section>

        <section
          :if={@catalog.status == :available}
          id="catalog-eligibility"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Capability</th>
                <th class="px-3 py-2">Kind</th>
                <th class="px-3 py-2">Mode</th>
                <th class="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody
              id="catalog-eligibility-stream"
              phx-update="stream"
              class="divide-y divide-slate-100"
            >
              <tr :for={{dom_id, entry} <- @streams.entries} id={dom_id}>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/catalog/#{entry.id}"}
                    class="font-medium text-slate-950 hover:underline"
                  >
                    {entry.title}
                  </.link>
                  <div class="text-xs text-slate-500">{entry.producer_revision_ref}</div>
                </td>
                <td class="px-3 py-2 text-slate-700">{entry.kind}</td>
                <td class="px-3 py-2 text-slate-700">{entry.configured_mode}</td>
                <td class="px-3 py-2 text-slate-700">{entry.status}</td>
              </tr>
            </tbody>
          </table>

          <p
            :if={@catalog.entries == []}
            id="catalog-empty"
            class="border-t border-slate-100 p-4 text-sm text-slate-600"
          >
            No executable capabilities are currently admitted.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp availability_reason(%{reason: reason}) when is_atom(reason) and not is_nil(reason),
    do: Atom.to_string(reason)

  defp availability_reason(_availability), do: "owner_unavailable"
end
