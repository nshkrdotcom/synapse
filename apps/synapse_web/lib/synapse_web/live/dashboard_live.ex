defmodule SynapseWeb.DashboardLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {runs, run_readback_state} =
      case Synapse.AgentRuns.list_runs() do
        {:ok, []} -> {[], :empty}
        {:ok, runs} -> {runs, :durable}
        {:error, _reason} -> {[], :unavailable}
      end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:feature_status, Synapse.feature_status())
      |> assign(:run_readback_state, run_readback_state)
      |> assign(:stats, stats(runs))
      |> assign(:recent_runs, Enum.take(runs, 5))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section id="dashboard-health" class="rounded border border-slate-200 bg-white p-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Product Boundary
              </p>
              <h1 class="mt-1 text-2xl font-semibold text-slate-950">NSHKR Agent</h1>
              <p class="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
                Run acceptance and readback pass through the configured AppKit runtime. This page never substitutes fixture or process-local state.
              </p>
            </div>

            <div class="grid min-w-72 grid-cols-2 gap-2 text-sm">
              <div :for={{label, value} <- @stats} class="rounded border border-slate-200 p-3">
                <div class="text-xs uppercase tracking-wide text-slate-500">{label}</div>
                <div class="mt-1 text-lg font-semibold text-slate-950">{value}</div>
              </div>
            </div>
          </div>
        </section>

        <section
          :if={@run_readback_state == :unavailable}
          id="dashboard-run-readback-unavailable"
          class="rounded border border-red-200 bg-red-50 p-4 text-sm text-red-900"
        >
          Durable run readback is unavailable. No cached run summary is displayed.
        </section>

        <section
          :if={@run_readback_state == :empty}
          id="dashboard-run-readback-empty"
          class="rounded border border-slate-200 bg-white p-4 text-sm text-slate-600"
        >
          No durable runs have been accepted yet.
        </section>

        <section
          :if={@run_readback_state == :durable}
          id="dashboard-active-runs"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Recent durable runs
            </h2>
            <.icon name="hero-play-circle" class="size-5 text-slate-500" />
          </div>

          <div class="mt-4 overflow-hidden rounded border border-slate-200">
            <table class="w-full text-left text-sm">
              <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th class="px-3 py-2">Run</th>
                  <th class="px-3 py-2">State</th>
                  <th class="px-3 py-2">Surface</th>
                </tr>
              </thead>
              <tbody id="dashboard-run-rows" class="divide-y divide-slate-100">
                <tr :for={run <- @recent_runs} id={"dashboard-run-#{run.id}"}>
                  <td class="px-3 py-2 font-medium text-slate-950">{run.ref}</td>
                  <td class="px-3 py-2 text-slate-700">{run.state}</td>
                  <td class="px-3 py-2 text-slate-500">{run.surface}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-3">
          <div id="dashboard-run-readback" class="rounded border border-slate-200 bg-white p-4">
            <div class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Run readback
            </div>
            <p class="mt-3 text-sm text-slate-700">{@run_readback_state}</p>
          </div>
          <div id="dashboard-review-status" class="rounded border border-slate-200 bg-white p-4">
            <div class="text-sm font-semibold uppercase tracking-wide text-slate-500">Reviews</div>
            <p class="mt-3 text-sm text-slate-600">Not activated in the durable acceptance slice.</p>
          </div>
          <div id="dashboard-operations-status" class="rounded border border-slate-200 bg-white p-4">
            <div class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Operations
            </div>
            <p class="mt-3 text-sm text-slate-600">No local operational truth is maintained.</p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp stats(runs) do
    [
      {"Durable runs", length(runs)},
      {"Reviews", "inactive"},
      {"Memory", "inactive"},
      {"Evidence", "inactive"}
    ]
  end
end
