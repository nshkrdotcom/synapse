defmodule SynapseWeb.EvidenceIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Evidence")
      |> assign(:replay, Synapse.Evidence.replay_bundle())
      |> stream(:evidence, Synapse.Evidence.list_evidence())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Evidence</h1>
          <p class="mt-1 text-sm text-slate-600">
            Fixture-backed receipt, evidence, and replay projections.
          </p>
        </section>

        <section id="evidence-list" class="overflow-hidden rounded border border-slate-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Evidence</th>
                <th class="px-3 py-2">Kind</th>
                <th class="px-3 py-2">Status</th>
                <th class="px-3 py-2">Receipt</th>
              </tr>
            </thead>
            <tbody id="evidence-stream" phx-update="stream" class="divide-y divide-slate-100">
              <tr :for={{dom_id, item} <- @streams.evidence} id={dom_id}>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/evidence/#{item.id}"}
                    class="font-medium text-slate-950 hover:underline"
                  >
                    {item.evidence_ref}
                  </.link>
                </td>
                <td class="px-3 py-2 text-slate-700">{item.evidence_kind}</td>
                <td class="px-3 py-2 text-slate-700">{item.status}</td>
                <td class="px-3 py-2 text-slate-500">{item.receipt_ref || "missing"}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="replay-links" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Replay</h2>
          <div class="mt-3 space-y-2 text-sm">
            <div :for={link <- @replay.replay_links} class="flex items-center justify-between gap-3">
              <span class="font-medium text-slate-950">{link.label}</span>
              <span class="text-slate-600">{link.ref}</span>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
