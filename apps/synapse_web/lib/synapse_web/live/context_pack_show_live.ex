defmodule SynapseWeb.ContextPackShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.ContextPacks.get_context_pack(id) do
        {:ok, pack} ->
          socket
          |> assign(:page_title, "Context Pack")
          |> assign(:pack, pack)
          |> assign(:surface_status, Synapse.ContextPacks.surface_status())
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Context Pack")
          |> assign(:pack, nil)
          |> assign(:surface_status, Synapse.ContextPacks.surface_status())
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section :if={@pack} class="rounded border border-slate-200 bg-white p-5">
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@pack.ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">Context Pack</h1>
          <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-3">
            <div>
              <dt class="text-slate-500">Mode</dt>
              <dd class="mt-1 font-medium text-slate-950">{@pack.mode}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Surface</dt>
              <dd class="mt-1 font-medium text-slate-950">{@surface_status.status}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Hash</dt>
              <dd class="mt-1 font-medium text-slate-950">{@pack.context_hash}</dd>
            </div>
          </dl>
        </section>

        <section :if={@pack} class="grid gap-4 lg:grid-cols-2">
          <.bucket id="context-included-items" title="Included" entries={@pack.included} />
          <.bucket id="context-denied-items" title="Denied" entries={@pack.denied} />
          <.bucket id="context-stale-items" title="Stale" entries={@pack.stale} />
          <.bucket id="context-revoked-items" title="Revoked" entries={@pack.revoked} />
          <.bucket id="context-candidate-items" title="Candidates" entries={@pack.candidates} />
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :entries, :list, required: true

  def bucket(assigns) do
    ~H"""
    <section id={@id} class="rounded border border-slate-200 bg-white p-4">
      <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">{@title}</h2>
      <div class="mt-3 divide-y divide-slate-100">
        <div :for={entry <- @entries} class="py-3">
          <div class="font-medium text-slate-950">{entry.ref}</div>
          <div class="mt-1 text-sm text-slate-600">{entry.state}</div>
          <div class="mt-2 flex flex-wrap gap-2 text-xs">
            <span
              :for={reason <- Map.get(entry, :reason_codes, [])}
              class="rounded bg-slate-100 px-2 py-1 text-slate-700"
            >
              {reason}
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
