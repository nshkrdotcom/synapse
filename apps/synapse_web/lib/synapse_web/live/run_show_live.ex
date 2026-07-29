defmodule SynapseWeb.RunShowLive do
  use SynapseWeb, :live_view

  alias AppKit.Core.SurfaceError

  @control_actions %{
    "pause" => :pause,
    "resume" => :resume,
    "cancel" => :cancel,
    "retry" => :retry,
    "supersede" => :supersede
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Run")
      |> assign(:requested_run_ref, id)
      |> assign(:control_message, nil)
      |> assign(:control_error, nil)
      |> load_run(id, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, %{assigns: %{run: run}} = socket)
      when is_map(run) do
    {:noreply, load_run(socket, run.ref, cursor: run.cursor)}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, socket}

  def handle_event(
        "control",
        %{"action" => action_name},
        %{assigns: %{run: %{control: %{row_version: version}} = run}} = socket
      )
      when is_integer(version) and version > 0 do
    with {:ok, action} <- Map.fetch(@control_actions, action_name),
         true <- action in run.available_controls,
         true <- control_executable?(action),
         {:ok, result} <-
           Synapse.AgentRuns.control_run(
             run.ref,
             action,
             %{expected_control_row_version: version},
             []
           ) do
      socket =
        socket
        |> assign(:control_message, result.message)
        |> assign(:control_error, nil)
        |> load_run(run.ref, cursor: run.cursor)

      {:noreply, socket}
    else
      false ->
        {:noreply,
         assign(socket, :control_error, "This control requires a new governed attempt identity.")}

      :error ->
        {:noreply, assign(socket, :control_error, "Unsupported run control.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:control_message, nil)
         |> assign(:control_error, error_message(reason))}
    end
  end

  def handle_event("control", _params, socket),
    do: {:noreply, assign(socket, :control_error, "Reload durable state before controlling.")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section
          :if={@readback_state == :unavailable}
          id="run-show-unavailable"
          class="rounded border border-red-200 bg-red-50 p-5 text-red-900"
        >
          <h1 class="text-lg font-semibold">Durable run readback is unavailable</h1>
          <p class="mt-2 text-sm">{@error_message}</p>
        </section>

        <section
          :if={@readback_state == :conflict}
          id="run-show-conflict"
          class="rounded border border-amber-200 bg-amber-50 p-5 text-amber-900"
        >
          <h1 class="text-lg font-semibold">Run readback conflict</h1>
          <p class="mt-2 text-sm">{@error_message}</p>
        </section>

        <section
          :if={@readback_state == :not_found}
          id="run-show-not-found"
          class="rounded border border-slate-200 bg-white p-5 text-slate-900"
        >
          <h1 class="text-lg font-semibold">Run not found</h1>
          <p class="mt-2 text-sm">{@error_message}</p>
        </section>

        <section
          :if={@readback_state == :error}
          id="run-show-error"
          class="rounded border border-red-200 bg-red-50 p-5 text-red-900"
        >
          <h1 class="text-lg font-semibold">Run could not be loaded</h1>
          <p class="mt-2 text-sm">{@error_message}</p>
        </section>

        <div :if={@readback_state == :snapshot} id="run-durable-snapshot" class="space-y-6">
          <section class="rounded border border-slate-200 bg-white p-5">
            <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <p
                  id="run-show-ref"
                  class="text-xs font-semibold uppercase tracking-wide text-slate-500"
                >
                  {@run.ref}
                </p>
                <h1 id="run-show-title" class="mt-1 text-2xl font-semibold text-slate-950">
                  {@run.title}
                </h1>
                <p :if={@run.goal_summary} class="mt-2 text-sm leading-6 text-slate-600">
                  {@run.goal_summary}
                </p>
              </div>

              <button
                id="run-refresh-button"
                type="button"
                phx-click="refresh"
                class="inline-flex items-center gap-2 rounded border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100"
              >
                <.icon name="hero-arrow-path" class="size-5" /> Refresh durable state
              </button>
            </div>
          </section>

          <section class="grid gap-4 lg:grid-cols-3">
            <div id="run-show-state" class="rounded border border-slate-200 bg-white p-4">
              <div class="text-xs uppercase tracking-wide text-slate-500">State</div>
              <div class="mt-1 text-lg font-semibold text-slate-950">{@run.state}</div>
            </div>
            <div id="run-show-workflow" class="rounded border border-slate-200 bg-white p-4">
              <div class="text-xs uppercase tracking-wide text-slate-500">Workflow</div>
              <div class="mt-1 break-all text-sm font-semibold text-slate-950">
                {@run.workflow_ref || "pending durable handoff"}
              </div>
            </div>
            <div id="run-show-persistence" class="rounded border border-slate-200 bg-white p-4">
              <div class="text-xs uppercase tracking-wide text-slate-500">Persistence</div>
              <div class="mt-1 text-lg font-semibold text-slate-950">durable</div>
            </div>
          </section>

          <section id="run-control-state" class="rounded border border-slate-200 bg-white p-4">
            <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                  Durable control
                </h2>
                <div class="mt-2 text-lg font-semibold text-slate-950">
                  {@run.control.state || "not available"}
                </div>
                <p id="run-control-version" class="mt-1 text-sm text-slate-600">
                  Row version {@run.control.row_version || "unavailable"}
                </p>
              </div>

              <div id="run-control-actions" class="flex flex-wrap gap-2">
                <button
                  :for={action <- @run.available_controls}
                  id={"run-#{action}-button"}
                  type="button"
                  phx-click="control"
                  phx-value-action={action}
                  disabled={!control_executable?(action)}
                  class={[
                    "inline-flex items-center rounded border px-3 py-2 text-sm font-semibold",
                    control_executable?(action) &&
                      "border-slate-300 text-slate-700 hover:bg-slate-100",
                    !control_executable?(action) &&
                      "cursor-not-allowed border-slate-200 bg-slate-50 text-slate-400"
                  ]}
                >
                  {control_label(action)}
                </button>
              </div>
            </div>

            <p
              :if={@run.control.deadline_at}
              id="run-control-deadline"
              class="mt-3 text-sm text-slate-600"
            >
              Deadline: {@run.control.deadline_at}
            </p>
            <p :if={@control_message} id="run-control-accepted" class="mt-3 text-sm text-emerald-700">
              {@control_message}
            </p>
            <p :if={@control_error} id="run-control-error" class="mt-3 text-sm text-red-700">
              {@control_error}
            </p>
          </section>

          <section
            :if={@run.ambiguous?}
            id="run-control-ambiguous"
            class="rounded border border-amber-300 bg-amber-50 p-4 text-amber-950"
          >
            <h2 class="font-semibold">External outcome is ambiguous</h2>
            <p class="mt-1 text-sm">
              No effect will be replayed while the durable owner reconciles the existing operation.
            </p>
            <p :if={@run.control.external_operation_ref} class="mt-2 break-all text-xs">
              {@run.control.external_operation_ref}
            </p>
          </section>

          <section
            :if={@run.degraded?}
            id="run-control-degraded"
            class="rounded border border-orange-300 bg-orange-50 p-4 text-orange-950"
          >
            <h2 class="font-semibold">Recovery is degraded</h2>
            <p class="mt-1 text-sm">
              {@run.control.last_error || "Operator review is required before another effect."}
            </p>
          </section>

          <section id="run-cursor-state" class="rounded border border-slate-200 bg-white p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Durable event cursor
            </h2>
            <dl class="mt-3 grid gap-3 text-sm md:grid-cols-3">
              <div>
                <dt class="text-slate-500">Cursor</dt>
                <dd id="run-cursor-ref" class="mt-1 break-all font-medium text-slate-950">
                  {@run.cursor.cursor_ref}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Ledger</dt>
                <dd id="run-cursor-ledger" class="mt-1 break-all font-medium text-slate-950">
                  {@run.cursor.ledger_ref}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Last sequence</dt>
                <dd id="run-cursor-sequence" class="mt-1 font-medium text-slate-950">
                  {@run.cursor.last_seq_seen}
                </dd>
              </div>
            </dl>
          </section>

          <section id="run-turn-snapshot" class="rounded border border-slate-200 bg-white p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Accepted turns
            </h2>
            <p id="run-turn-count" class="mt-2 text-sm text-slate-700">
              {length(@run.turns)} durable turn(s)
            </p>
          </section>

          <section id="run-events" class="rounded border border-slate-200 bg-white p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Durable timeline
            </h2>
            <p :if={@run.events == []} id="run-events-empty" class="mt-3 text-sm text-slate-600">
              No events after this cursor.
            </p>
            <ol :if={@run.events != []} id="run-event-list" class="mt-3 space-y-3 text-sm">
              <li
                :for={event <- @run.events}
                id={"run-event-#{event.event_seq}"}
                class="rounded border border-slate-200 p-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <span class="font-medium text-slate-950">{event.event_kind}</span>
                  <span class="text-slate-500">sequence {event.event_seq}</span>
                </div>
                <p class="mt-1 text-slate-600">{event.summary}</p>
              </li>
            </ol>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_run(socket, run_ref, opts) do
    case Synapse.AgentRuns.get_run(run_ref, opts) do
      {:ok, run} ->
        socket
        |> assign(:run, run)
        |> assign(:readback_state, :snapshot)
        |> assign(:error_message, nil)

      {:error, reason} ->
        socket
        |> assign(:run, nil)
        |> assign(:readback_state, error_state(reason))
        |> assign(:error_message, error_message(reason))
    end
  end

  defp error_state(%SurfaceError{kind: :conflict}), do: :conflict
  defp error_state(%SurfaceError{kind: :not_found}), do: :not_found

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
       when reason in [
              :app_kit_backend_unavailable,
              :app_kit_routing_unavailable,
              :durable_run_projection_unavailable
            ],
       do: "The durable AppKit runtime did not return a committed run snapshot."

  defp error_message(_reason), do: "The run could not be read through AppKit."

  defp control_executable?(action), do: action in [:pause, :resume, :cancel]

  defp control_label(:pause), do: "Pause"
  defp control_label(:resume), do: "Resume"
  defp control_label(:cancel), do: "Cancel"
  defp control_label(:retry), do: "Retry"
  defp control_label(:supersede), do: "Supersede"
end
