defmodule SynapseWeb.RunShowLive do
  use SynapseWeb, :live_view

  alias AppKit.Core.SurfaceError

  @catch_up_interval_ms 1_000
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
      |> assign(:turn_submission_token, next_turn_submission_token())
      |> assign(:turn_result, nil)
      |> assign(:turn_error, nil)
      |> assign(:provisional_turn, nil)
      |> assign(:stream_state, :loading)
      |> assign(:stream_error, nil)
      |> load_run(id, [])

    if connected?(socket) and is_map(socket.assigns[:run]) do
      :ok = Synapse.AgentRuns.subscribe(socket.assigns.run.ref)
      schedule_catch_up()
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, %{assigns: %{run: run}} = socket)
      when is_map(run) do
    {:noreply, load_run(socket, run.ref, cursor: run.cursor)}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, socket}

  def handle_event(
        "submit-turn",
        %{"turn" => attrs},
        %{assigns: %{run: run}} = socket
      )
      when is_map(run) do
    opts = [
      submission_token: socket.assigns.turn_submission_token,
      cursor_ref: run.cursor.cursor_ref
    ]

    attrs = Map.put(attrs, "kind", "user_input")

    case Synapse.Turns.submit_turn(run.ref, attrs, opts) do
      {:ok, %{accepted?: true} = result} ->
        provisional_turn = %{
          command_ref: result.command_ref,
          summary: Map.get(attrs, "input_summary"),
          baseline_turn_count: length(run.turns)
        }

        socket =
          socket
          |> assign(:turn_result, result)
          |> assign(:turn_error, nil)
          |> assign(:provisional_turn, provisional_turn)
          |> assign(:turn_submission_token, next_turn_submission_token())
          |> load_run(run.ref, cursor: run.cursor)

        :ok = Synapse.AgentRuns.notify_changed(run.ref)
        {:noreply, socket}

      {:ok, _other} ->
        {:noreply,
         socket
         |> assign(:turn_result, nil)
         |> assign(:turn_error, "AppKit did not return a durable turn acceptance.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:turn_result, nil)
         |> assign(:turn_error, error_message(reason))}
    end
  end

  def handle_event("submit-turn", _params, socket) do
    {:noreply, assign(socket, :turn_error, "Reload durable state before submitting a turn.")}
  end

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
  def handle_info(:durable_run_catch_up, socket) do
    socket = refresh_from_cursor(socket)
    schedule_catch_up()
    {:noreply, socket}
  end

  def handle_info(
        {:synapse_agent_run_changed, run_ref},
        %{assigns: %{run: %{ref: run_ref}}} = socket
      ) do
    {:noreply, refresh_from_cursor(socket)}
  end

  def handle_info({:synapse_agent_run_changed, _other_run_ref}, socket), do: {:noreply, socket}

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
          <section
            :if={@stream_state == :degraded}
            id="run-stream-degraded"
            class="rounded border border-amber-300 bg-amber-50 p-4 text-amber-950"
          >
            <h2 class="font-semibold">Durable catch-up is temporarily unavailable</h2>
            <p class="mt-1 text-sm">
              The last committed snapshot remains visible. No provisional event is treated as truth.
            </p>
            <p :if={@stream_error} class="mt-2 text-sm">{@stream_error}</p>
          </section>

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

          <section
            id="run-turn-snapshot"
            class="space-y-4 rounded border border-slate-200 bg-white p-4"
          >
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Committed turns
              </h2>
              <p id="run-turn-count" class="mt-2 text-sm text-slate-700">
                {length(@run.turns)} durable turn(s)
              </p>
            </div>

            <ol
              :if={@run.turns != []}
              id="run-turn-list"
              class="space-y-3 text-sm"
            >
              <li
                :for={turn <- @run.turns}
                id={turn_dom_id(turn)}
                class="rounded border border-slate-200 p-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <span class="font-medium text-slate-950">Turn {turn.sequence}</span>
                  <span class="text-slate-500">{turn.status}</span>
                </div>
                <p class="mt-1 break-all text-xs text-slate-500">{turn.ref}</p>
                <p :if={turn.summary} class="mt-2 text-slate-700">{turn.summary}</p>
              </li>
            </ol>

            <section
              :if={@provisional_turn}
              id="run-turn-provisional"
              class="rounded border border-sky-200 bg-sky-50 p-3 text-sm text-sky-950"
            >
              <p class="font-medium">Turn accepted; waiting for committed readback</p>
              <p class="mt-1 break-all text-xs">{@provisional_turn.command_ref}</p>
              <p :if={@provisional_turn.summary} class="mt-2">{@provisional_turn.summary}</p>
            </section>

            <p
              :if={@turn_result && !@provisional_turn}
              id="run-turn-committed"
              class="rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900"
            >
              The accepted turn is now present in committed AppKit readback.
            </p>

            <p
              :if={@turn_error}
              id="run-turn-error"
              class="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800"
            >
              {@turn_error}
            </p>

            <form id="run-turn-form" phx-submit="submit-turn" class="space-y-3">
              <div>
                <label for="run-turn-input" class="block text-sm font-medium text-slate-700">
                  Continue the run
                </label>
                <textarea
                  id="run-turn-input"
                  name="turn[input_summary]"
                  rows="4"
                  required
                  class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                ></textarea>
              </div>
              <button
                id="run-turn-submit-button"
                type="submit"
                class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
              >
                <.icon name="hero-paper-airplane" class="size-5" /> Submit durable turn
              </button>
            </form>
          </section>

          <section id="run-artifacts" class="rounded border border-slate-200 bg-white p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Durable artifacts
            </h2>
            <p
              :if={@run.artifacts == []}
              id="run-artifacts-empty"
              class="mt-3 text-sm text-slate-600"
            >
              No artifact references are present in committed readback.
            </p>
            <ol
              :if={@run.artifacts != []}
              id="run-artifact-list"
              class="mt-3 space-y-3 text-sm"
            >
              <li
                :for={artifact <- @run.artifacts}
                id={artifact_dom_id(artifact)}
                class="rounded border border-slate-200 p-3"
              >
                <div class="font-medium text-slate-950">{artifact.kind}</div>
                <p class="mt-1 break-all text-xs text-slate-500">{artifact.ref}</p>
              </li>
            </ol>
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
                <p :if={event.payload_ref} class="mt-1 break-all text-xs text-slate-500">
                  {event.payload_ref}
                </p>
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
        run = merge_run(Map.get(socket.assigns, :run), run)

        socket
        |> assign(:run, run)
        |> assign(:readback_state, :snapshot)
        |> assign(:error_message, nil)
        |> assign(:stream_state, :current)
        |> assign(:stream_error, nil)
        |> reconcile_provisional_turn()

      {:error, reason} ->
        case Map.get(socket.assigns, :run) do
          run when is_map(run) ->
            socket
            |> assign(:stream_state, :degraded)
            |> assign(:stream_error, error_message(reason))

          _other ->
            socket
            |> assign(:run, nil)
            |> assign(:readback_state, error_state(reason))
            |> assign(:error_message, error_message(reason))
            |> assign(:stream_state, :unavailable)
            |> assign(:stream_error, error_message(reason))
        end
    end
  end

  defp refresh_from_cursor(%{assigns: %{run: run}} = socket) when is_map(run) do
    load_run(socket, run.ref, cursor: run.cursor)
  end

  defp refresh_from_cursor(socket), do: socket

  defp merge_run(%{ref: run_ref} = previous, %{ref: run_ref} = current) do
    current
    |> Map.put(:events, merge_rows(previous.events, current.events, &event_key/1))
    |> Map.put(:artifacts, merge_rows(previous.artifacts, current.artifacts, & &1.ref))
  end

  defp merge_run(_previous, current), do: current

  defp merge_rows(previous, current, key_fun) do
    (List.wrap(previous) ++ List.wrap(current))
    |> Enum.uniq_by(key_fun)
    |> Enum.sort_by(key_fun)
  end

  defp event_key(event), do: {event.event_seq, event.event_ref}

  defp reconcile_provisional_turn(
         %{assigns: %{provisional_turn: %{baseline_turn_count: baseline}, run: run}} = socket
       )
       when length(run.turns) > baseline do
    assign(socket, :provisional_turn, nil)
  end

  defp reconcile_provisional_turn(socket), do: socket

  defp schedule_catch_up do
    Process.send_after(self(), :durable_run_catch_up, @catch_up_interval_ms)
  end

  defp next_turn_submission_token do
    "turn-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp turn_dom_id(turn), do: "run-turn-" <> stable_dom_token(turn.ref)
  defp artifact_dom_id(artifact), do: "run-artifact-" <> stable_dom_token(artifact.ref)

  defp stable_dom_token(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
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
