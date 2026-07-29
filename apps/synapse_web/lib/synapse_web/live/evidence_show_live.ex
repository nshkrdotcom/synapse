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
          |> assign(:error, nil)

        {:error, reason} ->
          socket
          |> assign(:page_title, "Evidence")
          |> assign(:evidence, nil)
          |> assign(:receipt, nil)
          |> assign(:error, error_message(reason))
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
          <p class="break-words text-xs font-semibold uppercase tracking-wide text-slate-500">
            {@evidence.evidence_ref}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-950">{@evidence.evidence_kind}</h1>
          <p class="mt-2 text-sm text-slate-600">{@evidence.status}</p>
        </section>

        <section
          :if={@evidence}
          id="evidence-lineage"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Lineage</h2>
          <dl class="mt-3 grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-slate-500">Run</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence.run_ref || "not projected"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Operation</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence[:operation_ref] || "not projected"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Artifact</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence[:artifact_ref] || "not projected"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Content</dt>
              <dd class="break-words font-medium text-slate-950">
                {@evidence.content_ref || "not retained"}
              </dd>
            </div>
          </dl>
        </section>

        <section
          :if={@receipt}
          id="receipt-summary"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Receipt</h2>
          <p class="mt-2 break-words text-sm text-slate-700">{@receipt.receipt_ref}</p>
          <p class="mt-1 text-sm text-slate-600">{@receipt.state}</p>
          <p class="mt-1 break-words text-xs text-slate-500">{@receipt.attempt_ref}</p>
        </section>

        <section
          :if={@evidence && is_nil(@receipt) && @evidence.receipt_ref}
          id="receipt-unavailable"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <p class="text-sm text-amber-800">receipt_projection_unavailable</p>
        </section>

        <section
          :if={@error}
          id="evidence-detail-unavailable"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <p class="text-sm font-medium text-amber-800">{@error}</p>
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

  defp error_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_message(_reason), do: "evidence_surface_unavailable"
end
