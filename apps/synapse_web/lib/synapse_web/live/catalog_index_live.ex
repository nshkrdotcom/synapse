defmodule SynapseWeb.CatalogIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    catalog = Synapse.Catalog.catalog()

    socket =
      socket
      |> assign(:page_title, "Catalog")
      |> assign(:catalog, catalog)
      |> stream(:entries, Synapse.Catalog.list_entries())

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
            Capability eligibility projected through product-safe AppKit DTOs.
          </p>
        </section>

        <section
          id="catalog-eligibility"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Capability</th>
                <th class="px-3 py-2">Kind</th>
                <th class="px-3 py-2">Status</th>
                <th class="px-3 py-2">Residency</th>
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
                  <div class="text-xs text-slate-500">{entry.eligibility_ref}</div>
                </td>
                <td class="px-3 py-2 text-slate-700">{entry.kind}</td>
                <td class="px-3 py-2 text-slate-700">{entry.status}</td>
                <td class="px-3 py-2 text-slate-500">{entry.posture.residency}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="catalog-model-list" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Model Profiles</h2>
          <div class="mt-3 flex flex-wrap gap-2 text-xs">
            <span
              :for={model <- @catalog.model_catalog.model_profiles}
              class="rounded bg-slate-100 px-2 py-1 text-slate-700"
            >
              {model.model_profile_ref}
            </span>
          </div>
        </section>

        <section id="catalog-skill-list" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Skill Profiles</h2>
          <div class="mt-3 flex flex-wrap gap-2 text-xs">
            <span
              :for={skill <- @catalog.skills}
              class="rounded bg-slate-100 px-2 py-1 text-slate-700"
            >
              {skill.skill_ref}
            </span>
          </div>
        </section>

        <section id="catalog-economics-disabled" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Assignment</h2>
          <p class="mt-2 text-sm text-slate-600">
            {@catalog.assignment_status.reason}
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
