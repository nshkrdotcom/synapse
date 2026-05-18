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
                  <dt class="text-slate-500">Content hash</dt>
                  <dd class="font-medium text-slate-950">{@memory.projection.content_hash}</dd>
                </div>
                <div class="flex flex-col gap-1 sm:flex-row sm:justify-between">
                  <dt class="text-slate-500">Redaction policy</dt>
                  <dd class="font-medium text-slate-950">
                    {@memory.projection.redaction_policy_ref}
                  </dd>
                </div>
              </dl>
              <p class="mt-4 text-sm text-slate-700">
                {@memory.projection.redacted_excerpt || "No excerpt is exportable for this memory."}
              </p>
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
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >
                  <option value="helpful">Helpful</option>
                  <option value="not_helpful">Not helpful</option>
                </select>
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100"
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
