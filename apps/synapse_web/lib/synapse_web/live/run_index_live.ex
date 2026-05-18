defmodule SynapseWeb.RunIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Runs")
      |> stream(:runs, Synapse.AgentRuns.list_runs())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-slate-950">Runs</h1>
            <p class="mt-1 text-sm text-slate-600">
              Fixture-backed AppKit AgentIntake projections.
            </p>
          </div>

          <.link
            navigate={~p"/runs/new"}
            class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
          >
            <.icon name="hero-play-circle" class="size-5" /> Start Run
          </.link>
        </section>

        <section id="run-index-list" class="overflow-hidden rounded border border-slate-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Run</th>
                <th class="px-3 py-2">State</th>
                <th class="px-3 py-2">Authority</th>
                <th class="px-3 py-2">Surface</th>
              </tr>
            </thead>
            <tbody id="run-index-stream" phx-update="stream" class="divide-y divide-slate-100">
              <tr :for={{dom_id, run} <- @streams.runs} id={dom_id}>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/runs/#{run.id}"}
                    class="font-medium text-slate-950 hover:underline"
                  >
                    {run.title}
                  </.link>
                  <div class="text-xs text-slate-500">{run.ref}</div>
                </td>
                <td class="px-3 py-2 text-slate-700">{run.state}</td>
                <td class="px-3 py-2 text-slate-700">{run.authority_state}</td>
                <td class="px-3 py-2 text-slate-500">{run.surface}</td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
