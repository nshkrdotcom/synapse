defmodule SynapseWeb.TeamIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Teams")
      |> stream(:teams, Synapse.Teams.list_teams())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Teams</h1>
          <p class="mt-1 text-sm text-slate-600">
            Fixture-backed coordination and hive projections over AppKit DTO surfaces.
          </p>
        </section>

        <section id="team-index-list" class="overflow-hidden rounded border border-slate-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Team</th>
                <th class="px-3 py-2">State</th>
                <th class="px-3 py-2">Quorum</th>
                <th class="px-3 py-2">Surface</th>
              </tr>
            </thead>
            <tbody id="team-index-stream" phx-update="stream" class="divide-y divide-slate-100">
              <tr :for={{dom_id, team} <- @streams.teams} id={dom_id}>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/teams/#{team.id}"}
                    class="font-medium text-slate-950 hover:underline"
                  >
                    {team.title}
                  </.link>
                  <div class="text-xs text-slate-500">{team.ref}</div>
                </td>
                <td class="px-3 py-2 text-slate-700">{team.state}</td>
                <td class="px-3 py-2 text-slate-700">{team.join_barrier.quorum_state}</td>
                <td class="px-3 py-2 text-slate-500">{team.executable_surface}</td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
