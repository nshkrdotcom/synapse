defmodule SynapseWeb.ReviewShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Reviews.get_review(id) do
        {:ok, review} ->
          socket
          |> assign(:page_title, "Review")
          |> assign(:review, review)
          |> assign(:decision_result, nil)
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Review")
          |> assign(:review, fallback_review(id))
          |> assign(:decision_result, nil)
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("record_decision", %{"review" => attrs}, socket) do
    case Synapse.Reviews.record_decision(socket.assigns.review.decision_id, attrs) do
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
        <section class="rounded border border-slate-200 bg-white p-5">
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@review.decision_id}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@review.title}</h1>
          <div class="mt-3 flex flex-wrap gap-2 text-xs">
            <span class="rounded border border-slate-200 px-2 py-1 text-slate-700">
              {@review.status}
            </span>
            <span class="rounded border border-slate-200 px-2 py-1 text-slate-700">
              {@review.authority_state}
            </span>
            <span
              :if={@review.stale?}
              class="rounded border border-amber-200 px-2 py-1 text-amber-700"
            >
              stale
            </span>
            <span :if={@review.denied?} class="rounded border border-red-200 px-2 py-1 text-red-700">
              denied
            </span>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="space-y-4">
            <section class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Run</h2>
              <p class="mt-2 text-sm text-slate-700">{@review.run_ref}</p>
            </section>

            <section class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Context And Memory
              </h2>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-slate-500">Context</dt>
                  <dd class="font-medium text-slate-950">{@review.context_pack_ref}</dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-slate-500">Memory</dt>
                  <dd class="font-medium text-slate-950">{@review.memory_posture}</dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-slate-500">Tools</dt>
                  <dd class="font-medium text-slate-950">{@review.tool_posture}</dd>
                </div>
              </dl>
            </section>

            <section id="review-reason-codes" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Reason Codes
              </h2>
              <div class="mt-3 flex flex-wrap gap-2 text-xs">
                <span :for={reason <- @review.reason_codes} class="rounded bg-slate-100 px-2 py-1">
                  {reason}
                </span>
              </div>
            </section>

            <section class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Evidence</h2>
              <ul class="mt-3 space-y-2 text-sm text-slate-700">
                <li :for={ref <- @review.evidence_refs}>{ref}</li>
              </ul>
            </section>
          </div>

          <aside class="space-y-4">
            <section class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Decision
              </h2>
              <form id="review-decision-form" phx-submit="record_decision" class="mt-3 space-y-3">
                <select
                  name="review[decision]"
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >
                  <option value="accept">Accept</option>
                  <option value="reject">Reject</option>
                  <option value="waive">Waive</option>
                  <option value="expired">Expired</option>
                  <option value="escalate">Escalate</option>
                </select>

                <textarea
                  name="review[reason]"
                  rows="4"
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >Fixture operator decision.</textarea>

                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
                >
                  <.icon name="hero-check-circle" class="size-5" /> Record
                </button>
              </form>
            </section>

            <section id="review-decision-result" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Result</h2>
              <p :if={is_nil(@decision_result)} class="mt-2 text-sm text-slate-600">
                No decision submitted in this session.
              </p>
              <p :if={@decision_result} class="mt-2 text-sm text-slate-700">
                {@decision_result.status}: {@decision_result.message}
              </p>
              <p :if={@error} class="mt-2 text-sm font-medium text-red-700">{@error}</p>
            </section>
          </aside>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp fallback_review(id) do
    %{
      id: id,
      decision_id: "decision://fixture/#{id}",
      title: "Fixture review #{id}",
      status: :pending,
      authority_state: :authorized,
      run_ref: "run://fixture/#{id}",
      context_pack_ref: "context-pack://fixture/#{id}",
      memory_posture: :disabled,
      tool_posture: :fixture_projected,
      reason_codes: ["review_required"],
      evidence_refs: ["receipt://fixture/#{id}"],
      stale?: false,
      denied?: false
    }
  end
end
