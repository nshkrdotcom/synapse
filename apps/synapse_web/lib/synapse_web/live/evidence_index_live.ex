defmodule SynapseWeb.EvidenceIndexLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Synapse.Evidence.snapshot()

    socket =
      socket
      |> assign(:page_title, "Evidence")
      |> assign(:snapshot, snapshot)
      |> stream(:evidence, snapshot.evidence)
      |> stream(:artifacts, snapshot.artifacts,
        dom_id: &("artifact-" <> URI.encode_www_form(&1.artifact_ref))
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Evidence And Artifacts</h1>
          <p class="mt-1 text-sm text-slate-600">
            Retained refs and causal evidence from durable AppKit run projections.
          </p>
        </section>

        <section
          :if={@snapshot.status == :degraded}
          id="evidence-degraded"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-900">
            Evidence partially available
          </h2>
          <p class="mt-2 text-sm text-amber-800">
            {@snapshot.projection_error_count} durable run projection(s) could not be read.
          </p>
        </section>

        <section
          :if={@snapshot.status == :unavailable}
          id="evidence-unavailable"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-900">
            Evidence unavailable
          </h2>
          <p class="mt-2 text-sm text-amber-800">
            {availability_reason(@snapshot.availability)}
          </p>
        </section>

        <section
          :if={@snapshot.status != :unavailable}
          id="evidence-list"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Evidence</th>
                <th class="px-3 py-2">Kind</th>
                <th class="px-3 py-2">Status</th>
                <th class="px-3 py-2">Receipt</th>
              </tr>
            </thead>
            <tbody id="evidence-stream" phx-update="stream" class="divide-y divide-slate-100">
              <tr :for={{dom_id, item} <- @streams.evidence} id={dom_id}>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/evidence/#{item.id}"}
                    class="font-medium text-slate-950 hover:underline"
                  >
                    {item.evidence_ref}
                  </.link>
                </td>
                <td class="px-3 py-2 text-slate-700">{item.evidence_kind}</td>
                <td class="px-3 py-2 text-slate-700">{item.status}</td>
                <td class="px-3 py-2 text-slate-500">{item.receipt_ref || "not projected"}</td>
              </tr>
            </tbody>
          </table>

          <p
            :if={@snapshot.evidence == []}
            id="evidence-empty"
            class="border-t border-slate-100 p-4 text-sm text-slate-600"
          >
            No evidence refs are retained for the projected runs.
          </p>
        </section>

        <section
          :if={@snapshot.status != :unavailable}
          id="artifact-list"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Retained artifacts
          </h2>
          <div
            id="artifact-stream"
            phx-update="stream"
            class="mt-3 divide-y divide-slate-100 text-sm"
          >
            <div :for={{dom_id, artifact} <- @streams.artifacts} id={dom_id} class="py-3">
              <p class="break-words font-medium text-slate-950">{artifact.artifact_ref}</p>
              <p class="mt-1 text-slate-600">
                {artifact.kind} · {artifact.status} · retained={artifact.retained?}
              </p>
            </div>
          </div>
          <p :if={@snapshot.artifacts == []} id="artifact-empty" class="mt-3 text-sm text-slate-600">
            No retained artifact projections are available.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp availability_reason(%{reason: reason}) when is_atom(reason) and not is_nil(reason),
    do: Atom.to_string(reason)

  defp availability_reason(_availability), do: "owner_unavailable"
end
