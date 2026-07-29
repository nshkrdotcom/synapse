defmodule SynapseWeb.OperationsLive do
  use SynapseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    operations = Synapse.Evidence.operations()

    facts =
      case Synapse.Evidence.runtime_facts() do
        {:ok, facts} -> facts
        {:error, _reason} -> nil
      end

    socket =
      socket
      |> assign(:page_title, "Operations")
      |> assign(:operations, operations)
      |> assign(:facts, facts)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <section>
          <h1 class="text-2xl font-semibold text-slate-950">Operations</h1>
          <p class="mt-1 text-sm text-slate-600">
            Durable operation, ambiguity, recovery, and runtime health projections.
          </p>
        </section>

        <section
          :if={@operations.status == :degraded}
          id="operations-degraded"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-900">
            Runtime health degraded
          </h2>
          <p class="mt-2 text-sm text-amber-800">
            {availability_reason(@operations.availability)}
          </p>
        </section>

        <section
          :if={@operations.status == :unavailable}
          id="operations-unavailable"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-900">
            Operations unavailable
          </h2>
          <p class="mt-2 text-sm text-amber-800">
            {availability_reason(@operations.availability)}
          </p>
        </section>

        <section
          :if={@operations.status != :unavailable}
          id="operations-health"
          class="overflow-hidden rounded border border-slate-200 bg-white"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-3 py-2">Surface</th>
                <th class="px-3 py-2">State</th>
              </tr>
            </thead>
            <tbody id="operations-health-rows" class="divide-y divide-slate-100">
              <tr :for={row <- @operations.health_rows} id={"operation-health-#{row.id}"}>
                <td class="px-3 py-2 font-medium text-slate-950">{row.label}</td>
                <td class="px-3 py-2 text-slate-700">{state_text(row.state)}</td>
              </tr>
            </tbody>
          </table>
          <p
            :if={@operations.health_rows == []}
            id="operations-health-empty"
            class="border-t border-slate-100 p-4 text-sm text-slate-600"
          >
            No runtime health facts were projected.
          </p>
        </section>

        <section
          :if={@operations.status != :unavailable}
          id="operation-list"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Durable operations
          </h2>
          <div class="mt-3 divide-y divide-slate-100 text-sm">
            <article
              :for={operation <- @operations.operation_rows}
              id={operation_dom_id(operation.operation_ref)}
              class="py-3"
            >
              <p class="break-words font-medium text-slate-950">{operation.operation_ref}</p>
              <p class="mt-1 text-slate-600">
                {operation.kind} · {operation.state} · {availability_state(operation.availability)}
              </p>
              <p :if={operation.receipt_ref} class="mt-1 break-words text-xs text-slate-500">
                {operation.receipt_ref}
              </p>
            </article>
          </div>
          <p
            :if={@operations.operation_rows == []}
            id="operation-list-empty"
            class="mt-3 text-sm text-slate-600"
          >
            No durable operation projections are available.
          </p>
        </section>

        <section
          :if={@operations.status != :unavailable && @operations.operator_required != []}
          id="operator-required-list"
          class="rounded border border-amber-200 bg-amber-50 p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-amber-900">
            Operator attention
          </h2>
          <ul class="mt-3 space-y-2 text-sm text-amber-900">
            <li :for={operation <- @operations.operator_required}>
              {operation.operation_ref} · {operation.state} · {operation.operator_task_ref ||
                operation.external_operation_ref}
            </li>
          </ul>
        </section>

        <section
          :if={@operations.status != :unavailable}
          id="capability-health-list"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Capability posture
          </h2>
          <ul class="mt-3 space-y-2 text-sm text-slate-700">
            <li :for={capability <- @operations.capabilities}>
              {capability.capability_ref} · advertised={capability.advertised?} · {availability_state(
                capability.availability
              )}
            </li>
          </ul>
          <p
            :if={@operations.capabilities == []}
            id="capability-health-empty"
            class="mt-3 text-sm text-slate-600"
          >
            No per-run capability posture was projected.
          </p>
        </section>

        <section
          :if={@facts}
          id="runtime-facts"
          class="rounded border border-slate-200 bg-white p-4"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Runtime facts
          </h2>
          <p class="mt-2 text-sm text-slate-700">{@facts.authority["state"]}</p>
          <p class="mt-1 text-sm text-slate-600">{@facts.aitrace["state"]}</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp operation_dom_id(ref), do: "operation-" <> URI.encode_www_form(ref)
  defp availability_state(%{state: state}), do: Atom.to_string(state)

  defp availability_reason(%{reason: reason}) when is_atom(reason) and not is_nil(reason),
    do: Atom.to_string(reason)

  defp availability_reason(%{reason_ref: reason_ref}) when is_binary(reason_ref), do: reason_ref
  defp availability_reason(_availability), do: "owner_unavailable"

  defp state_text(value) when is_binary(value), do: value
  defp state_text(value) when is_atom(value), do: Atom.to_string(value)
  defp state_text(value) when is_number(value), do: to_string(value)
  defp state_text(value) when is_boolean(value), do: to_string(value)
  defp state_text(_value), do: "projected"
end
