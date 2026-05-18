defmodule SynapseWeb.MemoryIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Memory")
      |> assign(:feedback_status, Synapse.Memory.feedback_status())
      |> assign(:context_status, Synapse.ContextPacks.surface_status())
      |> assign(:context_packs, Synapse.ContextPacks.list_context_packs())
      |> stream(:memories, Synapse.Memory.list_memories())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section class="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-slate-950">Memory</h1>
            <p class="mt-1 text-sm text-slate-600">
              Redacted AppKit memory DTO projections with fixture-backed context packs.
            </p>
          </div>

          <div
            id="memory-feedback-status"
            class="rounded border border-slate-200 bg-white px-3 py-2 text-sm"
          >
            <span class="text-slate-500">Feedback</span>
            <span class="ml-2 font-semibold text-slate-950">{@feedback_status.status}</span>
          </div>
        </section>

        <section
          id="memory-index-list"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Memory</th>
                <th class="px-3 py-2">State</th>
                <th class="px-3 py-2">Policy</th>
                <th class="px-3 py-2">Provenance</th>
              </tr>
            </thead>
            <tbody id="memory-index-stream" phx-update="stream" class="divide-y divide-slate-100">
              <tr :for={{dom_id, memory} <- @streams.memories} id={dom_id}>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/memory/#{memory.id}"}
                    class="font-medium text-slate-950 hover:underline"
                  >
                    {memory.title}
                  </.link>
                  <div class="text-xs text-slate-500">{memory.memory_ref}</div>
                </td>
                <td class="px-3 py-2 text-slate-700">{memory.state}</td>
                <td class="px-3 py-2 text-slate-700">{memory.redaction_policy_ref}</td>
                <td class="px-3 py-2 text-slate-500">{memory.provenance}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="context-pack-list" class="rounded border border-slate-200 bg-white p-4">
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Context Packs
            </h2>
            <span class="text-sm font-medium text-slate-700">{@context_status.status}</span>
          </div>

          <div class="mt-3 divide-y divide-slate-100">
            <div
              :for={pack <- @context_packs}
              class="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between"
            >
              <div>
                <.link
                  navigate={~p"/context-packs/#{pack.id}"}
                  class="font-medium text-slate-950 hover:underline"
                >
                  {pack.ref}
                </.link>
                <div class="text-xs text-slate-500">{pack.context_hash}</div>
              </div>
              <span class="text-sm text-slate-600">{pack.mode}</span>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
