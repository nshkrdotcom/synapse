defmodule SynapseWeb.RunIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {runs, readback_state} =
      case Synapse.AgentRuns.list_runs() do
        {:ok, []} -> {[], :empty}
        {:ok, runs} -> {runs, :snapshot}
        {:error, _reason} -> {[], :unavailable}
      end

    socket =
      socket
      |> assign(:page_title, "Runs")
      |> assign(:readback_state, readback_state)
      |> stream(:runs, runs)

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
              Durable AppKit run projections.
            </p>
          </div>

          <.link
            id="run-index-start-link"
            navigate={~p"/runs/new"}
            class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
          >
            <.icon name="hero-play-circle" class="size-5" /> Start Run
          </.link>
        </section>

        <section
          :if={@readback_state == :unavailable}
          id="run-index-unavailable"
          class="rounded border border-red-200 bg-red-50 p-4 text-sm text-red-900"
        >
          Durable run projections are unavailable. No cached or fixture rows are displayed.
        </section>

        <section
          :if={@readback_state == :empty}
          id="run-index-empty"
          class="rounded border border-slate-200 bg-white p-4 text-sm text-slate-600"
        >
          No durable runs have been accepted yet.
        </section>

        <section
          :if={@readback_state == :snapshot}
          id="run-index-list"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Run</th>
                <th class="px-3 py-2">State</th>
                <th class="px-3 py-2">Control</th>
                <th class="px-3 py-2">Updated</th>
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
                <td class="px-3 py-2 text-slate-700">{run.control_state || "unavailable"}</td>
                <td class="px-3 py-2 text-slate-700">{run.updated_at}</td>
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
