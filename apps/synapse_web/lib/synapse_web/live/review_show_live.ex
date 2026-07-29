defmodule SynapseWeb.ReviewShowLive do
  use SynapseWeb, :live_view

  alias AppKit.Core.SurfaceError

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Review")
      |> assign(:review, nil)
      |> assign(:review_id, id)
      |> assign(:effect, nil)
      |> assign(:effect_readback_state, :loading)
      |> assign(:effect_error, nil)
      |> assign(:decision_result, nil)
      |> assign(:readback_state, :loading)
      |> assign(:error, nil)
      |> load_review()

    if connected?(socket), do: schedule_refresh()

    {:ok, socket}
  end

  @impl true
  def handle_event("record_decision", %{"review" => attrs}, socket) do
    case Synapse.Reviews.record_decision(socket.assigns.review.decision_id, attrs) do
      {:ok, result} ->
        socket =
          socket
          |> assign(:decision_result, result)
          |> assign(:error, nil)
          |> load_review()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket |> assign(:error, error_message(reason)) |> assign(:decision_result, nil)}
    end
  end

  @impl true
  def handle_info(:refresh_review, socket) do
    schedule_refresh()
    {:noreply, load_review(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section
        :if={is_nil(@review)}
        id="review-load-error"
        data-state={@readback_state}
        class="rounded border border-red-200 bg-red-50 p-5"
      >
        <h1 class="text-xl font-semibold text-red-950">Review unavailable</h1>
        <p class="mt-2 text-sm text-red-800">
          The durable AppKit review <span class="font-mono">{@review_id}</span> could not be loaded.
        </p>
        <p class="mt-2 text-sm text-red-800">{@error}</p>
      </section>

      <div :if={@review} class="space-y-6">
        <section
          :if={@readback_state == :degraded}
          id="review-readback-degraded"
          class="rounded border border-amber-300 bg-amber-50 p-4 text-amber-950"
        >
          <h2 class="font-semibold">Review readback is temporarily degraded</h2>
          <p class="mt-1 text-sm">{@error}</p>
          <p class="mt-1 text-xs">
            The detail below is the last complete durable AppKit projection received by this view.
          </p>
        </section>

        <section
          id="review-summary"
          data-status={@review.status}
          data-authority-state={@review.authority_state}
          class="rounded border border-slate-200 bg-white p-5"
        >
          <p
            id="review-decision-ref"
            class="text-xs font-semibold uppercase tracking-wide text-slate-500"
          >
            {@review.decision_id}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@review.title}</h1>
          <div class="mt-3 flex flex-wrap gap-2 text-xs">
            <span id="review-status" class="rounded border border-slate-200 px-2 py-1 text-slate-700">
              {@review.status}
            </span>
            <span
              id="review-authority-state"
              class="rounded border border-slate-200 px-2 py-1 text-slate-700"
            >
              {@review.authority_state}
            </span>
            <span
              :if={@review.stale?}
              id="review-stale-state"
              class="rounded border border-amber-200 px-2 py-1 text-amber-700"
            >
              stale
            </span>
            <span
              :if={@review.denied?}
              id="review-denied-state"
              class="rounded border border-red-200 px-2 py-1 text-red-700"
            >
              denied
            </span>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="space-y-4">
            <section id="review-run-context" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Run</h2>
              <p class="mt-2 break-all text-sm text-slate-700">
                {present_or_absent(@review.run_ref)}
              </p>
            </section>

            <section id="review-context-memory" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Context And Memory
              </h2>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-slate-500">Context</dt>
                  <dd class="break-all font-medium text-slate-950">
                    {present_or_absent(@review.context_pack_ref)}
                  </dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-slate-500">Memory</dt>
                  <dd class="font-medium text-slate-950">
                    {present_or_absent(@review.memory_posture)}
                  </dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-slate-500">Tools</dt>
                  <dd class="font-medium text-slate-950">
                    {present_or_absent(@review.tool_posture)}
                  </dd>
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
                <span :if={@review.reason_codes == []} class="text-sm text-slate-500">
                  No reason code was present in durable readback.
                </span>
              </div>
            </section>

            <section id="review-evidence" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Evidence</h2>
              <ul :if={@review.evidence_refs != []} class="mt-3 space-y-2 text-sm text-slate-700">
                <li :for={ref <- @review.evidence_refs} class="break-all">{ref}</li>
              </ul>
              <p :if={@review.evidence_refs == []} class="mt-3 text-sm text-slate-500">
                No evidence reference was present in durable readback.
              </p>
            </section>

            <.governed_effect_panel
              :if={@effect}
              id="review-governed-effect"
              effects={[@effect]}
            />

            <section
              :if={
                @review.effect_ref &&
                  @effect_readback_state in [:unavailable, :degraded]
              }
              id="review-effect-readback-state"
              data-state={@effect_readback_state}
              class="rounded border border-amber-300 bg-amber-50 p-4 text-amber-950"
            >
              <h2 class="font-semibold">Governed effect readback unavailable</h2>
              <p class="mt-1 text-sm">{@effect_error}</p>
              <p :if={@effect} class="mt-1 text-xs">
                The effect panel above is the last complete durable AppKit projection received.
              </p>
              <p class="mt-2 break-all text-xs">{@review.effect_ref}</p>
            </section>
          </div>

          <aside class="space-y-4">
            <section id="review-decision" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Decision
              </h2>
              <form
                :if={
                  @review.allowed_decisions != [] &&
                    @readback_state == :available
                }
                id="review-decision-form"
                phx-submit="record_decision"
                class="mt-3 space-y-3"
              >
                <label for="review-decision-kind" class="block text-sm font-medium text-slate-700">
                  Action
                </label>
                <select
                  id="review-decision-kind"
                  name="review[decision]"
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >
                  <option :for={decision <- @review.allowed_decisions} value={decision}>
                    {decision_label(decision)}
                  </option>
                </select>

                <label for="review-decision-reason" class="block text-sm font-medium text-slate-700">
                  Reason
                </label>
                <textarea
                  id="review-decision-reason"
                  name="review[reason]"
                  rows="4"
                  required
                  class="w-full rounded border border-slate-300 px-3 py-2 text-sm text-slate-950"
                >Reviewed by the Synapse operator.</textarea>

                <button
                  id="review-decision-submit"
                  type="submit"
                  class="inline-flex items-center gap-2 rounded bg-slate-950 px-3 py-2 text-sm font-semibold text-white hover:bg-slate-800"
                >
                  <.icon name="hero-check-circle" class="size-5" /> Record durable decision
                </button>
              </form>

              <p
                :if={@review.allowed_decisions == []}
                id="review-decision-closed"
                class="mt-3 text-sm text-slate-600"
              >
                AppKit admits no further action for this durable review state.
              </p>
              <p
                :if={
                  @review.allowed_decisions != [] &&
                    @readback_state != :available
                }
                id="review-decision-readback-blocked"
                class="mt-3 text-sm text-amber-700"
              >
                Review actions are unavailable until current durable readback is restored.
              </p>
            </section>

            <section id="review-decision-result" class="rounded border border-slate-200 bg-white p-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
                Command Receipt
              </h2>
              <p :if={is_nil(@decision_result)} class="mt-2 text-sm text-slate-600">
                No review command submitted in this session.
              </p>
              <div :if={@decision_result} class="mt-2 space-y-1 text-sm text-slate-700">
                <p id="review-command-status">
                  {@decision_result.status}: {@decision_result.message}
                </p>
                <p class="text-xs text-slate-500">
                  Review state above is always reloaded from durable AppKit readback.
                </p>
              </div>
              <p :if={@error} class="mt-2 text-sm font-medium text-red-700">{@error}</p>
            </section>
          </aside>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp load_review(socket) do
    case Synapse.Reviews.get_review(socket.assigns.review_id) do
      {:ok, review} ->
        socket
        |> assign(:review, review)
        |> assign(:readback_state, :available)
        |> assign(:error, nil)
        |> load_effect(review)

      {:error, reason} ->
        state = if is_map(socket.assigns.review), do: :degraded, else: :unavailable

        socket
        |> assign(:readback_state, state)
        |> assign(:error, error_message(reason))
    end
  end

  defp load_effect(socket, %{effect_ref: nil}) do
    socket
    |> assign(:effect, nil)
    |> assign(:effect_readback_state, :not_applicable)
    |> assign(:effect_error, nil)
  end

  defp load_effect(socket, %{effect_lookup: nil}) do
    socket
    |> assign(:effect, nil)
    |> assign(:effect_readback_state, :unavailable)
    |> assign(
      :effect_error,
      "The durable review projection does not expose an AppKit effect lookup identity."
    )
  end

  defp load_effect(socket, review) do
    case Synapse.GovernedEffects.get_effect_for_review(review, []) do
      {:ok, effect} ->
        socket
        |> assign(:effect, effect)
        |> assign(:effect_readback_state, :available)
        |> assign(:effect_error, nil)

      {:error, reason} ->
        socket
        |> assign(:effect_readback_state, :degraded)
        |> assign(:effect_error, effect_error_message(reason))
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_review, @refresh_interval_ms)
  end

  defp decision_label(:accept), do: "Accept"
  defp decision_label(:reject), do: "Reject"
  defp decision_label(:waive), do: "Waive"
  defp decision_label(:escalate), do: "Escalate"

  defp present_or_absent(value) when is_binary(value) and value != "", do: value
  defp present_or_absent(value) when is_atom(value), do: Atom.to_string(value)
  defp present_or_absent(_value), do: "Not present in durable readback"

  defp error_message(%SurfaceError{message: message}), do: message

  defp error_message(reason)
       when reason in [
              :app_kit_backend_unavailable,
              :invalid_durable_review_projection,
              :invalid_durable_review_status,
              :invalid_durable_review_effect_payload
            ],
       do: "AppKit did not return a complete durable review projection."

  defp error_message(:review_decision_not_allowed),
    do: "AppKit readback no longer admits that review action."

  defp error_message(_reason),
    do: "The review command or readback could not be completed through AppKit."

  defp effect_error_message(%SurfaceError{message: message}), do: message

  defp effect_error_message(:invalid_durable_effect_projection),
    do: "AppKit returned an incomplete governed-effect projection."

  defp effect_error_message(_reason),
    do: "The durable governed effect could not be read through AppKit."
end
