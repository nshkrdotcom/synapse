defmodule SynapseWeb.OperationsLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Operations")
      |> assign(:operations, Synapse.Evidence.operations())
      |> assign(:facts, Synapse.Evidence.runtime_facts())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Operations</h1>
          <p class="mt-1 text-sm text-slate-600">
            Product health projections separate from replay/trace export.
          </p>
        </section>

        <section
          id="operations-health"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Surface</th>
                <th class="px-3 py-2">State</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr :for={row <- @operations.health_rows}>
                <td class="px-3 py-2 font-medium text-slate-950">{row.label}</td>
                <td class="px-3 py-2 text-slate-700">{row.state}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="aitrace-separation" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Trace Export</h2>
          <p class="mt-2 text-sm text-slate-700">
            {@operations.runtime_status.preflight["trace_export_metrics_truth"]}
          </p>
        </section>

        <section id="runtime-facts" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Runtime Facts</h2>
          <p class="mt-2 text-sm text-slate-700">{@facts.authority.state}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
