defmodule SynapseWeb.EvidenceShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    opts = evidence_opts()

    socket =
      case Synapse.Evidence.get_evidence(id, opts) do
        {:ok, evidence} ->
          socket
          |> assign(:page_title, "Evidence")
          |> assign(:evidence, evidence)
          |> assign(:receipt, receipt(evidence, opts))
          |> assign(:replay, Synapse.Evidence.replay_bundle())
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Evidence")
          |> assign(:evidence, nil)
          |> assign(:receipt, nil)
          |> assign(:replay, Synapse.Evidence.replay_bundle())
          |> assign(:error, inspect(reason))
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section
          :if={@evidence}
          id="evidence-detail"
          class="rounded border border-slate-200 bg-white p-5"
        >
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@evidence.evidence_ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@evidence.evidence_kind}</h1>
          <p class="mt-2 text-sm text-slate-600">{@evidence.status}</p>
        </section>

        <section
          :if={@evidence && @evidence.evidence_kind == "governed_effect"}
          id="governed-effect-evidence"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Governed Effect
          </h2>
          <dl class="mt-3 grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-slate-500">Effect</dt>
              <dd class="break-words font-medium text-slate-950">{@evidence.effect_ref}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Authority</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence.authority_ref || "pending"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Receipt</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence.receipt_ref || "pending"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Trace</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence.trace_summary_hash || @evidence.trace_ref || "pending"}
              </dd>
            </div>
          </dl>

          <div
            :if={is_map(@evidence.diagnostic_result)}
            id="governed-effect-diagnostic-result"
            class="mt-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900"
          >
            {@evidence.diagnostic_result["status"] || @evidence.diagnostic_result[:status]}
            <span class="text-emerald-700">
              {@evidence.diagnostic_result["summary"] || @evidence.diagnostic_result[:summary]}
            </span>
          </div>

          <ol id="governed-effect-evidence-timeline" class="mt-4 grid gap-2 text-xs sm:grid-cols-2">
            <li
              :for={entry <- @evidence.lifecycle_entries || []}
              class="rounded border border-slate-200 bg-slate-50 px-3 py-2"
            >
              {entry_status(entry)}
            </li>
          </ol>
        </section>

        <section
          :if={@receipt}
          id="receipt-summary"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Receipt</h2>
          <p class="mt-2 text-sm text-slate-700">{@receipt.receipt.receipt_ref}</p>
          <p class="mt-1 text-sm text-slate-600">{@receipt.receipt.receipt_state}</p>
        </section>

        <section
          :if={@evidence && is_nil(@receipt)}
          id="missing-evidence"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-800">
            Missing Evidence
          </h2>
          <p class="mt-2 text-sm text-amber-800">
            {@evidence.missing_reason || "receipt_not_available"}
          </p>
        </section>

        <section id="replay-bundle" class="rounded border border-slate-200 bg-white p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Replay Bundle</h2>
          <p class="mt-2 text-sm text-slate-700">{@replay.bundle.bundle_ref}</p>
          <p class="mt-1 text-sm text-slate-600">{@replay.bundle.decision_class}</p>
        </section>

        <section :if={@error} class="rounded border border-red-200 bg-red-50 p-4">
          <p class="text-sm font-medium text-red-700">{@error}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp receipt(%{receipt_ref: nil}, _opts), do: nil

  defp receipt(%{receipt_ref: receipt_ref}, opts) do
    case Synapse.Evidence.get_receipt(receipt_ref, opts) do
      {:ok, receipt} -> receipt
      {:error, _reason} -> nil
    end
  end

  defp evidence_opts do
    :synapse_web
    |> Application.get_env(__MODULE__, [])
    |> Keyword.take([:governed_effects])
  end

  defp entry_status(entry) when is_map(entry) do
    Map.get(entry, :status, Map.get(entry, "status", "unknown"))
  end

  defp entry_status(entry), do: to_string(entry)
end
