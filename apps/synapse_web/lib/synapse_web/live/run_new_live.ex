defmodule SynapseWeb.RunNewLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Start Run")
      |> assign(:result, nil)
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("start", %{"run" => attrs}, socket) do
    case Synapse.AgentRuns.start_run(attrs) do
      {:ok, result} ->
        {:noreply, socket |> assign(:result, result) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, inspect(reason)) |> assign(:result, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section class="rounded border border-slate-200 bg-white p-5">
          <h1 class="text-2xl font-semibold text-slate-950">Start Run</h1>
          <p class="mt-1 text-sm text-slate-600">
            Starts a fixture-backed run through AppKit AgentIntake.
          </p>

          <form id="run-start-form" phx-submit="start" class="mt-5 space-y-4">
            <div>
              <label for="run-title" class="block text-sm font-medium text-slate-700">Title</label>
              <input
                id="run-title"
                name="run[title]"
                type="text"
                value="Governed agent task"
                class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
              />
            </div>

            <div>
              <label for="run-goal" class="block text-sm font-medium text-slate-700">
                Goal Summary
              </label>
              <textarea
                id="run-goal"
                name="run[goal_summary]"
                rows="5"
                class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
              >Verify a product-safe AppKit run path.</textarea>
            </div>

            <div>
              <label for="run-team" class="block text-sm font-medium text-slate-700">
                Team Template
              </label>
              <select
                id="run-team"
                name="run[team_template_ref]"
                class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
              >
                <option value="standard_implementation">Standard Implementation</option>
                <option value="fast_review">Fast Review</option>
                <option value="high_risk_change">High-Risk Change</option>
                <option value="documentation_research">Documentation/Research</option>
              </select>
            </div>

            <button
              type="submit"
              class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
            >
              <.icon name="hero-play" class="size-5" /> Start
            </button>
          </form>

          <p :if={@error} id="run-start-error" class="mt-4 text-sm font-medium text-red-700">
            {@error}
          </p>
        </section>

        <section id="run-start-result" class="rounded border border-slate-200 bg-white p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Result</h2>

          <div :if={is_nil(@result)} class="mt-3 text-sm text-slate-600">
            No run submitted in this session.
          </div>

          <dl :if={@result} class="mt-3 space-y-2 text-sm">
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">State</dt>
              <dd class="font-medium text-slate-950">{@result.state}</dd>
            </div>
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">Run</dt>
              <dd class="font-medium text-slate-950">{@result.ref}</dd>
            </div>
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">Surface</dt>
              <dd class="font-medium text-slate-950">{@result.surface}</dd>
            </div>
          </dl>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
