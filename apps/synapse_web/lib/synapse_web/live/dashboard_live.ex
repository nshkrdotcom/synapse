defmodule SynapseWeb.DashboardLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:feature_status, Synapse.feature_status())
      |> assign(:bootstrap_status, Synapse.ProductBootstrap.fixture_status())
      |> assign(:stats, stats())
      |> assign(:recent_runs, recent_runs())
      |> assign(:pending_reviews, pending_reviews())

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
                Synapse is running as a headless AppKit product shell. Product installation, pack, and operational projections remain fixture-backed until AppKit live surfaces are proven for each feature.
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

        <section class="grid gap-4 lg:grid-cols-3">
          <div
            id="dashboard-active-runs"
            class="rounded border border-slate-200 bg-white p-4 lg:col-span-2"
          >
            <div class="flex items-center justify-between gap-3">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Active Runs
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
                <tbody class="divide-y divide-slate-100">
                  <tr :for={run <- @recent_runs}>
                    <td class="px-3 py-2 font-medium text-slate-950">{run.ref}</td>
                    <td class="px-3 py-2 text-slate-700">{run.state}</td>
                    <td class="px-3 py-2 text-slate-500">{run.surface}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div id="dashboard-pending-reviews" class="rounded border border-slate-200 bg-white p-4">
            <div class="flex items-center justify-between gap-3">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Pending Reviews
              </h2>
              <.icon name="hero-clipboard-document-check" class="size-5 text-slate-500" />
            </div>

            <div class="mt-4 space-y-3">
              <div :for={review <- @pending_reviews} class="rounded border border-slate-200 p-3">
                <div class="text-sm font-medium text-slate-950">{review.ref}</div>
                <div class="mt-1 text-xs text-slate-500">{review.reason}</div>
              </div>
            </div>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-3">
          <div id="dashboard-denials" class="rounded border border-slate-200 bg-white p-4">
            <div class="flex items-center gap-2 text-sm font-semibold uppercase tracking-wide text-slate-500">
              <.icon name="hero-shield-exclamation" class="size-5" /> Denials
            </div>
            <p class="mt-3 text-sm text-slate-600">No fixture denials recorded.</p>
          </div>

          <div id="installation-bootstrap-status" class="rounded border border-slate-200 bg-white p-4">
            <div class="flex items-center gap-2 text-sm font-semibold uppercase tracking-wide text-slate-500">
              <.icon name="hero-cube-transparent" class="size-5" /> Installation
            </div>
            <dl class="mt-3 space-y-2 text-sm">
              <div class="flex items-center justify-between gap-3">
                <dt class="text-slate-500">Status</dt>
                <dd class="font-medium text-slate-950">{@bootstrap_status.status}</dd>
              </div>
              <div class="flex items-center justify-between gap-3">
                <dt class="text-slate-500">Pack</dt>
                <dd class="font-medium text-slate-950">
                  {@bootstrap_status.pack_slug}@{@bootstrap_status.pack_version}
                </dd>
              </div>
              <div class="flex items-center justify-between gap-3">
                <dt class="text-slate-500">Install</dt>
                <dd class="font-medium text-slate-950">{@bootstrap_status.installation_id}</dd>
              </div>
            </dl>
          </div>

          <div id="operations-slo-list" class="rounded border border-slate-200 bg-white p-4">
            <div class="flex items-center gap-2 text-sm font-semibold uppercase tracking-wide text-slate-500">
              <.icon name="hero-chart-bar-square" class="size-5" /> Operations
            </div>
            <p class="mt-3 text-sm text-slate-600">
              Health is projected from product fixture state in Phase 1.
            </p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp stats do
    [
      {"Runs", "fixture"},
      {"Reviews", "fixture"},
      {"Memory", "disabled"},
      {"Teams", "roadmap"}
    ]
  end

  defp recent_runs do
    [
      %{ref: "run://fixture/phase-1", state: "ready", surface: "AppKit.AgentIntake"}
    ]
  end

  defp pending_reviews do
    [
      %{ref: "review://fixture/bootstrap", reason: "Phase 1 shell proof"}
    ]
  end
end
