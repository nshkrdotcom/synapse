defmodule SynapseWeb.EvidenceShowLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      case Synapse.Evidence.get_evidence(id) do
        {:ok, evidence} ->
          socket
          |> assign(:page_title, "Evidence")
          |> assign(:evidence, evidence)
          |> assign(:receipt, receipt(evidence))
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

  defp receipt(%{receipt_ref: nil}), do: nil

  defp receipt(%{receipt_ref: receipt_ref}) do
    case Synapse.Evidence.get_receipt(receipt_ref) do
      {:ok, receipt} -> receipt
      {:error, _reason} -> nil
    end
  end
end
