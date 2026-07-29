defmodule SynapseWeb.RunNewLive do
  use SynapseWeb, :live_view

  alias AppKit.Core.SurfaceError

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Start Run")
      |> assign(:submission_token, "run-#{System.unique_integer([:positive])}")
      |> assign(:result, nil)
      |> assign(:result_state, :idle)
      |> assign(:error_message, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("start", %{"run" => attrs}, socket) do
    case Synapse.AgentRuns.start_run(attrs, run_token: socket.assigns.submission_token) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:result, result)
         |> assign(:result_state, :accepted)
         |> assign(:error_message, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:result, nil)
         |> assign(:result_state, error_state(reason))
         |> assign(:error_message, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section class="rounded border border-slate-200 bg-white p-5">
          <h1 class="text-2xl font-semibold text-slate-950">Start Run</h1>
          <p class="mt-2 text-sm text-slate-600">
            Acceptance is committed by the durable AppKit runtime before it is shown here.
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
              >Verify a durable AppKit run acceptance path.</textarea>
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
              id="run-start-button"
              type="submit"
              class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
            >
              <.icon name="hero-play" class="size-5" /> Start
            </button>
          </form>
        </section>

        <section id="run-start-result" class="rounded border border-slate-200 bg-white p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Result</h2>

          <p :if={@result_state == :idle} id="run-start-idle" class="mt-3 text-sm text-slate-600">
            No run submitted in this session.
          </p>

          <dl :if={@result_state == :accepted} id="run-start-accepted" class="mt-3 space-y-2 text-sm">
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">State</dt>
              <dd class="font-medium text-slate-950">{@result.state}</dd>
            </div>
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">Run</dt>
              <dd id="run-start-run-ref" class="font-medium text-slate-950">{@result.ref}</dd>
            </div>
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">Workflow</dt>
              <dd id="run-start-workflow-ref" class="font-medium text-slate-950">
                {@result.workflow_ref}
              </dd>
            </div>
            <div class="flex items-center justify-between gap-3">
              <dt class="text-slate-500">Command</dt>
              <dd id="run-start-command-ref" class="font-medium text-slate-950">
                {@result.command_ref}
              </dd>
            </div>
            <div class="pt-2">
              <.link
                id="run-start-open-link"
                navigate={~p"/runs/#{@result.id}"}
                class="inline-flex items-center gap-2 rounded border border-slate-300 px-3 py-2 font-semibold text-slate-700 hover:bg-slate-100"
              >
                Open committed run <.icon name="hero-arrow-right" class="size-4" />
              </.link>
            </div>
          </dl>

          <section
            :if={@result_state == :conflict}
            id="run-start-conflict"
            class="mt-4 rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900"
          >
            {@error_message}
          </section>

          <section
            :if={@result_state == :unavailable}
            id="run-start-unavailable"
            class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800"
          >
            {@error_message}
          </section>

          <section
            :if={@result_state == :error}
            id="run-start-error"
            class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800"
          >
            {@error_message}
          </section>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp error_state(%SurfaceError{kind: :conflict}), do: :conflict

  defp error_state(%SurfaceError{kind: kind}) when kind in [:boundary, :transient],
    do: :unavailable

  defp error_state(reason)
       when reason in [
              :app_kit_backend_unavailable,
              :app_kit_routing_unavailable,
              :durable_run_projection_unavailable
            ],
       do: :unavailable

  defp error_state(_reason), do: :error

  defp error_message(%SurfaceError{message: message}), do: message

  defp error_message(reason)
       when reason in [:app_kit_backend_unavailable, :app_kit_routing_unavailable],
       do: "The durable AppKit runtime is unavailable. No run was accepted."

  defp error_message(:durable_run_projection_unavailable),
    do: "Durable run projection readback is unavailable."

  defp error_message(_reason), do: "The run request could not be accepted."
end
