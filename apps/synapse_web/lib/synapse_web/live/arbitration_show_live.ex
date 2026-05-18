defmodule SynapseWeb.ArbitrationShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Arbitration.get_session(id) do
        {:ok, session} ->
          socket
          |> assign(:page_title, "Arbitration")
          |> assign(:session, session)
          |> assign(:decision_result, nil)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Arbitration")
          |> assign(:session, nil)
          |> assign(:decision_result, nil)
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("record_decision", %{"decision" => attrs}, socket) do
    case Synapse.Arbitration.record_final_decision(socket.assigns.session.id, attrs) do
      {:ok, result} ->
        {:noreply, socket |> assign(:decision_result, result) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, inspect(reason)) |> assign(:decision_result, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section :if={@session} class="rounded border border-slate-200 bg-white p-5">
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@session.ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">Arbitration</h1>
          <p class="mt-2 text-sm text-slate-600">{@session.consensus_posture}</p>
        </section>

        <section
          :if={@session}
          id="arbitration-positions"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Positions</h2>
          <div class="mt-3 divide-y divide-slate-100">
            <div :for={position <- @session.positions} class="py-3">
              <div class="font-medium text-slate-950">{position.role_ref}</div>
              <div class="mt-1 text-sm text-slate-600">{position.stance}</div>
            </div>
          </div>
        </section>

        <section
          :if={@session}
          id="arbitration-consensus"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Consensus</h2>
          <p class="mt-2 text-sm text-slate-700">
            Quorum {@session.quorum.arrived_count}/{@session.quorum.required_count}: {@session.quorum.state}
          </p>
        </section>

        <section
          :if={@session}
          id="arbitration-memory-grants"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Memory Writes</h2>
          <p class="mt-2 text-sm text-slate-700">
            {@session.memory_write_status.status}: {@session.memory_write_status.reason}
          </p>
        </section>

        <section :if={@session} class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Final Decision
          </h2>
          <form id="arbitration-decision-form" phx-submit="record_decision" class="mt-3 space-y-3">
            <select
              name="decision[decision]"
              class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
            >
              <option value="accept">Accept</option>
              <option value="reject">Reject</option>
              <option value="escalate">Escalate</option>
            </select>
            <input
              type="text"
              name="decision[reason]"
              value="Consensus reviewed"
              class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
            />
            <button
              type="submit"
              class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
            >
              <.icon name="hero-check-circle" class="size-5" /> Record
            </button>
          </form>
          <p
            :if={@decision_result}
            id="arbitration-decision-result"
            class="mt-3 text-sm text-slate-700"
          >
            {@decision_result.status}
          </p>
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
