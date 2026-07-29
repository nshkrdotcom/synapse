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
            <div>
              <dt class="text-slate-500">Retrieval snapshot</dt>
              <dd class="mt-1 break-all font-medium text-slate-950">
                {@pack.retrieval_snapshot_ref || "proof-token pinned"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Context manifest artifact</dt>
              <dd class="mt-1 break-all font-medium text-slate-950">
                {@pack.context_manifest_artifact_ref || "not projected"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Owner snapshot epoch</dt>
              <dd class="mt-1 font-medium text-slate-950">{@pack.snapshot_epoch}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Commit LSN</dt>
              <dd class="mt-1 font-medium text-slate-950">{@pack.commit_lsn}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Run</dt>
              <dd class="mt-1 break-all font-medium text-slate-950">
                {@pack.run_ref || "not projected"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Trace</dt>
              <dd class="mt-1 break-all font-medium text-slate-950">
                {@pack.trace_id || "not projected"}
              </dd>
            </div>
          </dl>
        </section>

        <section
          :if={@pack}
          id="context-memory-manifest"
          class="grid gap-4 lg:grid-cols-2"
        >
          <div class="rounded border border-slate-200 bg-white p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Retrieval Manifest
            </h2>
            <dl class="mt-3 space-y-2 text-sm">
              <div>
                <dt class="text-slate-500">Working memory</dt>
                <dd class="mt-1 break-all font-medium text-slate-950">
                  {Enum.join(@pack.working_memory_refs, ", ")}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Episodic memory</dt>
                <dd class="mt-1 break-all font-medium text-slate-950">
                  {Enum.join(@pack.episodic_memory_refs, ", ")}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Exclusions</dt>
                <dd class="mt-1 break-all font-medium text-slate-950">
                  {if @pack.exclusion_refs == [],
                    do: "none projected",
                    else: Enum.join(@pack.exclusion_refs, ", ")}
                </dd>
              </div>
            </dl>
          </div>

          <div class="rounded border border-slate-200 bg-white p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
              Owner Lifecycle State
            </h2>
            <dl class="mt-3 space-y-2 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">Retention</dt>
                <dd class="font-medium text-slate-950">
                  {Enum.join(@pack.retention_states, ", ")}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">Deletion</dt>
                <dd class="font-medium text-slate-950">
                  {Enum.join(@pack.deletion_states, ", ")}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">Reindex</dt>
                <dd class="font-medium text-slate-950">
                  {Enum.join(@pack.reindex_states, ", ")}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">Index revision</dt>
                <dd class="font-medium text-slate-950">
                  {@pack.index_revision || "not projected"}
                </dd>
              </div>
            </dl>
          </div>
        </section>

        <section :if={@pack} class="grid gap-4 lg:grid-cols-2">
          <.bucket id="context-included-items" title="Included" entries={@pack.included} />
          <.bucket id="context-denied-items" title="Denied" entries={@pack.denied} />
          <.bucket id="context-stale-items" title="Stale" entries={@pack.stale} />
          <.bucket id="context-revoked-items" title="Revoked" entries={@pack.revoked} />
          <.bucket id="context-candidate-items" title="Candidates" entries={@pack.candidates} />
          <.bucket id="context-degraded-items" title="Degraded" entries={@pack.degraded} />
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:entries, :list, required: true)

  def bucket(assigns) do
    ~H"""
    <section id={@id} class="rounded border border-slate-200 bg-white p-4">
      <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">{@title}</h2>
      <div class="mt-3 divide-y divide-slate-100">
        <div :for={entry <- @entries} data-memory-entry class="py-3">
          <div class="font-medium text-slate-950">{entry.ref}</div>
          <div class="mt-1 text-sm text-slate-600">
            {entry.memory_class} · {entry.state}
          </div>
          <dl class="mt-2 grid gap-1 text-xs text-slate-500">
            <div>artifact: {entry.content_artifact_ref || "not projected"}</div>
            <div>retention: {entry.retention_state}</div>
            <div>deletion: {entry.deletion_state}</div>
            <div>index: {entry.reindex_state}</div>
          </dl>
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
