defmodule SynapseWeb.GovernedEffectComponents do
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, required: true
  attr :effects, :list, default: []
  attr :timelines, :map, default: %{}

  def governed_effect_panel(assigns) do
    ~H"""
    <section :if={@effects != []} id={@id} class="rounded border border-slate-200 bg-white p-4">
      <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">
        Governed Effects
      </h2>

      <div class="mt-4 space-y-4">
        <article
          :for={effect <- @effects}
          id={"#{@id}-effect-#{dom_fragment(field(effect, :effect_ref))}"}
          class="rounded border border-slate-100 bg-slate-50 p-3"
        >
          <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h3 class="text-sm font-semibold text-slate-950">{field(effect, :effect_type)}</h3>
              <p class="mt-1 text-xs text-slate-500">{field(effect, :effect_ref)}</p>
            </div>
            <span class="w-fit rounded border border-emerald-200 bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-800">
              {display_status(field(effect, :status))}
            </span>
          </div>

          <dl class="mt-3 grid gap-2 text-xs sm:grid-cols-2">
            <div>
              <dt class="text-slate-500">Authority</dt>
              <dd class="mt-0.5 break-words font-medium text-slate-800">
                {field(effect, :authority_ref) || "pending"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Receipt</dt>
              <dd class="mt-0.5 break-words font-medium text-slate-800">
                {field(effect, :receipt_ref) || "pending"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Dispatch</dt>
              <dd class="mt-0.5 break-words font-medium text-slate-800">
                {field(effect, :dispatch_ref) || "pending"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Trace</dt>
              <dd class="mt-0.5 break-words font-medium text-slate-800">
                {field(effect, :trace_ref) || "pending"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Evidence</dt>
              <dd class="mt-0.5 break-words font-medium text-slate-800">
                {evidence_refs(effect)}
              </dd>
            </div>
          </dl>

          <ol
            id={"#{@id}-timeline-#{dom_fragment(field(effect, :effect_ref))}"}
            class="mt-4 grid gap-2 text-xs sm:grid-cols-2"
          >
            <li
              :for={entry <- timeline_entries(@timelines, effect)}
              id={"#{@id}-timeline-#{dom_fragment(field(effect, :effect_ref))}-#{field(entry, :sequence)}"}
              data-status={field(entry, :status)}
              class="rounded border border-slate-200 bg-white px-3 py-2"
            >
              <span class="font-semibold text-slate-900">
                {display_status(field(entry, :status))}
              </span>
              <span class="ml-2 text-slate-500">{field(entry, :event_kind)}</span>
              <div class="mt-1 break-words text-slate-500">{field(entry, :entry_hash)}</div>
            </li>
          </ol>
        </article>
      </div>
    </section>
    """
  end

  defp timeline_entries(timelines, effect) do
    effect_ref = field(effect, :effect_ref)

    case Map.get(timelines, effect_ref) do
      %{entries: entries} when is_list(entries) -> entries
      _other -> []
    end
  end

  defp field(nil, _key), do: nil

  defp field(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp display_status("receipt_received"), do: "received"

  defp display_status(status) when is_atom(status),
    do: status |> Atom.to_string() |> display_status()

  defp display_status(status) when is_binary(status), do: String.replace(status, "_", " ")
  defp display_status(nil), do: "pending"
  defp display_status(status), do: to_string(status)

  defp evidence_refs(effect) do
    case field(effect, :evidence_refs) do
      refs when is_list(refs) and refs != [] -> Enum.join(refs, ", ")
      _other -> "pending"
    end
  end

  defp dom_fragment(nil), do: "unknown"

  defp dom_fragment(value) do
    value
    |> to_string()
    |> String.replace("://", "-")
    |> String.replace("/", "-")
    |> String.replace(":", "-")
    |> String.replace(".", "-")
    |> String.replace("_", "-")
  end
end
