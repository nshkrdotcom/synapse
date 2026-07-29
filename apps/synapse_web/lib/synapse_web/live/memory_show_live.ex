defmodule SynapseWeb.MemoryShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Memory.get_memory(id) do
        {:ok, memory} ->
          socket
          |> assign(:page_title, "Memory")
          |> assign(:memory, memory)
          |> assign(:feedback_status, Synapse.Memory.feedback_status())
          |> assign(:feedback_result, nil)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Memory")
          |> assign(:memory, nil)
          |> assign(:feedback_status, Synapse.Memory.feedback_status())
          |> assign(:feedback_result, nil)
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("submit_feedback", %{"feedback" => attrs}, socket) do
    case Synapse.Memory.write_feedback(attrs) do
      {:ok, result} ->
        {:noreply, socket |> assign(:feedback_result, result) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, inspect(reason)) |> assign(:feedback_result, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section :if={@memory} class="rounded border border-slate-200 bg-white p-5">
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@memory.memory_ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@memory.title}</h1>
          <p class="mt-2 text-sm text-slate-600">
            State: <span class="font-medium text-slate-950">{@memory.state}</span>
          </p>
        </section>

        <section :if={@memory} class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="space-y-4">
            <section id="memory-projection" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Projection
              </h2>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Proof hash</dt>
                  <dd class="break-all font-medium text-slate-950">{@memory.content_hash}</dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Redaction posture</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.redaction_policy_ref}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Memory class</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.memory_class}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Owner artifact</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.content_artifact_ref || "not projected"}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Content digest</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.content_digest || "not projected"}
                  </dd>
                </div>
              </dl>
              <p class="mt-4 text-sm text-slate-700">
                No fragment body crosses the AppKit product boundary.
              </p>
            </section>

            <section
              id="memory-retrieval-snapshot"
              class="rounded border border-slate-200 bg-white p-4"
            >
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Immutable Retrieval Snapshot
              </h2>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Proof token</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.snapshot.proof_token_ref}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Retrieval snapshot</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.snapshot.retrieval_snapshot_ref || "not projected"}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Owner snapshot epoch</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.snapshot.snapshot_epoch}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Commit LSN</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.snapshot.commit_lsn}
                  </dd>
                </div>
              </dl>
            </section>

            <section id="memory-provenance" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Provenance
              </h2>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Source contract</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.provenance_projection.source_contract_name}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Commit LSN</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.provenance_projection.commit_lsn}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Source</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.provenance_label || "owner-projected provenance"}
                  </dd>
                </div>
              </dl>
            </section>

            <section id="memory-lifecycle" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Retention, Deletion, and Reindex
              </h2>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Retention</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.lifecycle.retention_state}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Retention policy</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.lifecycle.retention_policy_ref ||
                      @memory.lifecycle.retention_reason}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Deletion</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.lifecycle.deletion_state}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Deletion detail</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {@memory.lifecycle.deleted_at || @memory.lifecycle.deletion_reason ||
                      "not projected"}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Index</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.lifecycle.reindex_state}
                  </dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Index revision</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.lifecycle.index_revision || @memory.lifecycle.reindex_reason}
                  </dd>
                </div>
              </dl>
            </section>

            <section id="memory-reason-codes" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Reason Codes
              </h2>
              <div class="mt-3 flex flex-wrap gap-2 text-xs">
                <span
                  :for={reason <- @memory.reason_codes}
                  class="rounded bg-slate-100 px-2 py-1 text-slate-700"
                >
                  {reason}
                </span>
                <span :if={@memory.reason_codes == []} class="text-sm text-slate-500">
                  none
                </span>
              </div>
            </section>
          </div>

          <aside class="space-y-4">
            <section
              id="memory-feedback-disabled"
              class="rounded border border-slate-200 bg-white p-4"
            >
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Feedback
              </h2>
              <p class="mt-2 text-sm text-slate-600">
                {@feedback_status.reason}
              </p>
              <form id="memory-feedback-form" phx-submit="submit_feedback" class="mt-3 space-y-3">
                <input type="hidden" name="feedback[memory_ref]" value={@memory.memory_ref} />
                <select
                  name="feedback[feedback_kind]"
                  disabled
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >
                  <option value="helpful">Helpful</option>
                  <option value="not_helpful">Not helpful</option>
                </select>
                <button
                  type="submit"
                  disabled
                  class="inline-flex cursor-not-allowed items-center gap-2 rounded border border-slate-200 bg-slate-50 px-3 py-2 text-sm font-semibold text-slate-400"
                >
                  <.icon name="hero-chat-bubble-left-ellipsis" class="size-5" /> Record Feedback
                </button>
              </form>
              <p :if={@feedback_result} class="mt-3 text-sm text-slate-700">
                {@feedback_result.status}
              </p>
            </section>
          </aside>
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
