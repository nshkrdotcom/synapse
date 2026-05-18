defmodule SynapseWeb.RunShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.AgentRuns.get_run(id) do
        {:ok, run} ->
          socket
          |> assign(:page_title, "Run")
          |> assign(:run, run)
          |> assign(:command_result, nil)
          |> assign(:turn_result, nil)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Run")
          |> assign(:run, Synapse.AgentRuns.fixture_detail(id))
          |> assign(:command_result, nil)
          |> assign(:turn_result, nil)
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("submit_turn", %{"turn" => attrs}, socket) do
    case Synapse.Turns.submit_turn(socket.assigns.run.ref, attrs) do
      {:ok, result} ->
        {:noreply, socket |> assign(:turn_result, result) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, inspect(reason)) |> assign(:turn_result, nil)}
    end
  end

  def handle_event("refresh", _params, socket) do
    case Synapse.AgentRuns.refresh_run(socket.assigns.run.ref) do
      {:ok, result} ->
        {:noreply, socket |> assign(:command_result, result) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  def handle_event("cancel", _params, socket) do
    case Synapse.AgentRuns.cancel_run(socket.assigns.run.ref) do
      {:ok, result} ->
        {:noreply, socket |> assign(:command_result, result) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section class="rounded border border-slate-200 bg-white p-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
                {@run.ref}
              </p>
              <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@run.title}</h1>
              <p class="mt-2 text-sm leading-6 text-slate-600">{@run.goal_summary}</p>
            </div>

            <div class="flex gap-2">
              <button
                id="run-refresh-button"
                type="button"
                phx-click="refresh"
                class="inline-flex items-center gap-2 rounded border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100"
              >
                <.icon name="hero-arrow-path" class="size-5" /> Refresh
              </button>
              <button
                id="run-cancel-button"
                type="button"
                phx-click="cancel"
                class="inline-flex items-center gap-2 rounded border border-red-200 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50"
              >
                <.icon name="hero-no-symbol" class="size-5" /> Cancel
              </button>
            </div>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-3">
          <div class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">State</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">{@run.state}</div>
          </div>
          <div class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Authority</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">{@run.authority_state}</div>
          </div>
          <div class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Budget</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">{@run.budget_state}</div>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="space-y-4">
            <section id="run-context-pack" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Context</h2>
              <p class="mt-2 text-sm text-slate-700">{@run.context_pack_ref}</p>
            </section>

            <section id="run-memory-projection" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Memory</h2>
              <p class="mt-2 text-sm text-slate-700">{@run.memory_state}</p>
            </section>

            <section id="run-tool-grants" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Tool Grants
              </h2>
              <p class="mt-2 text-sm text-slate-700">
                Fixture grant projection pending catalog phase.
              </p>
            </section>

            <section id="run-events" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Timeline</h2>
              <ol class="mt-3 space-y-2 text-sm">
                <li :for={event <- @run.events} class="flex items-center justify-between gap-3">
                  <span class="font-medium text-slate-950">{event.kind}</span>
                  <span class="text-slate-500">{event.status}</span>
                </li>
              </ol>
            </section>
          </div>

          <aside class="space-y-4">
            <section class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Turn</h2>
              <form id="run-turn-form" phx-submit="submit_turn" class="mt-3 space-y-3">
                <textarea
                  name="turn[input_summary]"
                  rows="4"
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >Continue with the current plan.</textarea>
                <input type="hidden" name="turn[kind]" value="user_input" />
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
                >
                  <.icon name="hero-paper-airplane" class="size-5" /> Submit
                </button>
              </form>
            </section>

            <section id="run-command-result" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Command Result
              </h2>
              <p
                :if={is_nil(@command_result) and is_nil(@turn_result)}
                class="mt-2 text-sm text-slate-600"
              >
                No command submitted in this session.
              </p>
              <p :if={@command_result} class="mt-2 text-sm text-slate-700">
                {@command_result.command_kind}: {@command_result.status}
              </p>
              <p :if={@turn_result} class="mt-2 text-sm text-slate-700">
                {@turn_result.command_kind}: {@turn_result.status}
              </p>
              <p :if={@error} class="mt-2 text-sm font-medium text-red-700">{@error}</p>
            </section>
          </aside>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
