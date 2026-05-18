defmodule SynapseWeb.TeamShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Teams.get_team(id) do
        {:ok, team} ->
          socket
          |> assign(:page_title, "Team")
          |> assign(:team, team)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Team")
          |> assign(:team, nil)
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section :if={@team} class="rounded border border-slate-200 bg-white p-5">
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@team.ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@team.title}</h1>
          <p class="mt-2 text-sm text-slate-600">
            Control: <span class="font-medium text-slate-950">{@team.control_status.status}</span>
          </p>
        </section>

        <section
          :if={@team}
          id="team-member-state"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Members</h2>
          <div class="mt-3 grid gap-3 lg:grid-cols-3">
            <div :for={member <- @team.members} class="rounded border border-slate-200 p-3">
              <div class="font-medium text-slate-950">{member.role_ref}</div>
              <div class="mt-1 text-sm text-slate-600">{member.state}</div>
              <div class="mt-1 text-xs text-slate-500">{member.current_turn_ref}</div>
            </div>
          </div>
        </section>

        <section :if={@team} class="grid gap-4 lg:grid-cols-3">
          <div id="team-join-barrier" class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Join Barrier</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">
              {@team.join_barrier.state}
            </div>
          </div>
          <div id="team-quorum-state" class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Quorum</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">
              {@team.join_barrier.arrived_count}/{@team.join_barrier.required_count}
              {@team.join_barrier.quorum_state}
            </div>
          </div>
          <div id="team-fanout-fanin" class="rounded border border-slate-200 bg-white p-4">
            <div class="text-xs uppercase tracking-wide text-slate-500">Fanout/Fanin</div>
            <div class="mt-1 text-lg font-semibold text-slate-950">
              {@team.fanout.state}/{@team.fanin.state}
            </div>
          </div>
        </section>

        <section
          :if={@team}
          id="team-hive-projection"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Hive Projection
          </h2>
          <p class="mt-2 text-sm text-slate-700">{@team.hive_projection.projection_ref}</p>
          <p class="mt-1 text-sm text-slate-600">{@team.hive_projection.redaction_posture}</p>
        </section>

        <section
          :if={@team}
          id="team-arbitration-link"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <.link
            navigate={~p"/arbitration/phase-7"}
            class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
          >
            <.icon name="hero-scale" class="size-5" /> Arbitration
          </.link>
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
