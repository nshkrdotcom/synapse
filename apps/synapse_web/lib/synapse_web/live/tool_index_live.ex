defmodule SynapseWeb.ToolIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    catalog = Synapse.Catalog.catalog()

    socket =
      socket
      |> assign(:page_title, "Tools")
      |> assign(:catalog, catalog)
      |> assign(:models, catalog.model_catalog.model_profiles)
      |> stream(:tool_grants, catalog.tool_grants)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Tools And Models</h1>
          <p class="mt-1 text-sm text-slate-600">
            Fixture-backed AppKit catalog, model, skill, and budget projections.
          </p>
        </section>

        <section id="tool-grant-list" class="overflow-hidden rounded border border-slate-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Skill</th>
                <th class="px-3 py-2">Grant</th>
                <th class="px-3 py-2">Budget</th>
                <th class="px-3 py-2">Reasons</th>
              </tr>
            </thead>
            <tbody id="tool-grant-stream" phx-update="stream" class="divide-y divide-slate-100">
              <tr :for={{dom_id, grant} <- @streams.tool_grants} id={dom_id}>
                <td class="px-3 py-2">
                  <div class="font-medium text-slate-950">{grant.skill_ref}</div>
                  <div class="text-xs text-slate-500">{Enum.join(grant.tool_refs, ", ")}</div>
                </td>
                <td class="px-3 py-2 text-slate-700">{grant.status}</td>
                <td class="px-3 py-2 text-slate-700">{grant.budget_profile_ref}</td>
                <td class="px-3 py-2 text-slate-500">{Enum.join(grant.reason_codes, ", ")}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="model-grant-list" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Models</h2>
          <div id="model-grant-stream" class="mt-3 divide-y divide-slate-100">
            <div :for={model <- @models} id={model.model_profile_ref} class="py-3">
              <div class="font-medium text-slate-950">{model.model_profile_ref}</div>
              <div class="mt-1 text-sm text-slate-600">
                {Enum.join(Enum.map(model.operation_classes, &Atom.to_string/1), ", ")}
              </div>
            </div>
          </div>
        </section>

        <section id="catalog-budget-posture" class="grid gap-4 lg:grid-cols-3">
          <div class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Run Budget</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">
              {@catalog.budgets.run_budget.decision_class}
            </div>
          </div>
          <div class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Context Budget</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">
              {@catalog.budgets.context_budget.residual_units} turns
            </div>
          </div>
          <div class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Denied Effect</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">
              {@catalog.budgets.denied_effect_budget.decision_class}
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
