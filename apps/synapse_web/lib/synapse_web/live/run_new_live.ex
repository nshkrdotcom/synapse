defmodule SynapseWeb.RunNewLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Start Run")
      |> assign(:result, nil)
      |> assign(:effect_timelines, %{})
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("start", %{"run" => attrs}, socket) do
    attrs = run_attrs(attrs)

    case Synapse.AgentRuns.start_run(attrs, run_opts(attrs)) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:result, result)
         |> assign(:effect_timelines, effect_timelines(result))
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, inspect(reason))
         |> assign(:result, nil)
         |> assign(:effect_timelines, %{})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section class="rounded border border-slate-200 bg-white p-5">
          <h1 class="text-2xl font-semibold text-slate-950">Start Run</h1>

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

            <div>
              <label for="run-diagnostic-lane" class="block text-sm font-medium text-slate-700">
                Diagnostic Lane
              </label>
              <select
                id="run-diagnostic-lane"
                name="run[diagnostic_lane]"
                class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
              >
                <option value="">None</option>
                <option value="echo">Echo</option>
                <option value="probe">Probe</option>
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
            <div
              :if={Map.has_key?(@result, :feature_status)}
              class="flex items-center justify-between gap-3"
            >
              <dt class="text-slate-500">Feature</dt>
              <dd id="run-start-feature-status" class="font-medium text-slate-950">
                {@result.feature_status}
              </dd>
            </div>
            <div
              :if={Map.has_key?(@result, :effect_governance_mode)}
              class="flex items-center justify-between gap-3"
            >
              <dt class="text-slate-500">Governance</dt>
              <dd class="font-medium text-slate-950">{@result.effect_governance_mode}</dd>
            </div>
          </dl>

          <section
            :if={@result && Map.get(@result, :feature_status) == :staging_live_error}
            id="run-start-error-state"
            class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800"
          >
            {inspect(@result.error.reason)}
          </section>

          <div :if={@result} class="mt-4">
            <.governed_effect_panel
              id="run-start-governed-effects"
              effects={Map.get(@result, :governed_effects, [])}
              timelines={@effect_timelines}
            />
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp run_attrs(attrs) when is_map(attrs) do
    case map_value(attrs, :diagnostic_lane) do
      "" -> Map.delete(attrs, "diagnostic_lane")
      nil -> attrs
      _lane -> attrs
    end
  end

  defp run_opts(attrs) do
    if diagnostic_lane?(attrs) do
      :synapse_web
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:diagnostic_run_opts, [])
    else
      []
    end
  end

  defp diagnostic_lane?(attrs) do
    case map_value(attrs, :diagnostic_lane) do
      lane when lane in ["echo", "probe", :echo, :probe] -> true
      _other -> false
    end
  end

  defp effect_timelines(run) when is_map(run) do
    opts =
      :synapse_web
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:governed_effect_opts, [])

    run
    |> Map.get(:governed_effects, [])
    |> Enum.reduce(%{}, fn effect, timelines ->
      effect_ref = map_value(effect, :effect_ref)

      cond do
        effect_ref in [nil, ""] -> timelines
        opts == [] -> timelines
        true -> put_timeline(timelines, effect_ref, opts)
      end
    end)
  end

  defp effect_timelines(_run), do: %{}

  defp put_timeline(timelines, effect_ref, opts) do
    case Synapse.GovernedEffects.get_effect_timeline(effect_ref, opts) do
      {:ok, timeline} -> Map.put(timelines, effect_ref, timeline)
      {:error, _reason} -> timelines
    end
  end

  defp map_value(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
