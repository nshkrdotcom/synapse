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
          id={effect_dom_id(@id, effect)}
          data-status={field(effect, :status)}
          data-availability={availability_state(effect)}
          class="rounded border border-slate-200 bg-slate-50 p-4"
        >
          <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h3 class="text-sm font-semibold text-slate-950">
                {display_status(field(effect, :effect_type) || :tool_effect)}
              </h3>
              <p class="mt-1 break-all text-xs text-slate-500">{field(effect, :effect_ref)}</p>
            </div>
            <span class={status_class(field(effect, :status))}>
              {display_status(field(effect, :status))}
            </span>
          </div>

          <dl class="mt-4 grid gap-3 text-xs sm:grid-cols-2">
            <div>
              <dt class="text-slate-500">Owner operation</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :owner_execution_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Run</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :run_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Authority grant</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :grant_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Authority decision</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :decision_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Attempt</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :attempt_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Runtime execution</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :runtime_execution_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">External operation</dt>
              <dd class="mt-0.5 break-all font-medium text-slate-800">
                {present_or_absent(field(effect, :external_ref))}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Owner row version</dt>
              <dd class="mt-0.5 font-medium text-slate-800">
                {present_or_absent(field(effect, :row_version))}
              </dd>
            </div>
          </dl>

          <section
            id={effect_section_id(@id, effect, "review")}
            class="mt-4 rounded border border-slate-200 bg-white p-3"
          >
            <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Durable Review
            </h4>
            <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2">
              <div>
                <dt class="text-slate-500">Review</dt>
                <dd class="mt-0.5 break-all font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :review, :review_ref))}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Status</dt>
                <dd class="mt-0.5 font-medium text-slate-800">
                  {display_status(nested_field(effect, :review, :status))}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Review row version</dt>
                <dd class="mt-0.5 font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :review, :row_version))}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Accepted actor</dt>
                <dd class="mt-0.5 break-all font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :review, :accepted_actor_ref))}
                </dd>
              </div>
            </dl>
          </section>

          <section
            id={effect_section_id(@id, effect, "operation")}
            class="mt-4 rounded border border-slate-200 bg-white p-3"
          >
            <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Exact Reviewed Operation
            </h4>
            <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2">
              <div>
                <dt class="text-slate-500">Manifest</dt>
                <dd class="mt-0.5 break-all font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :pinned_tool_manifest, :manifest_ref))}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Manifest hash</dt>
                <dd class="mt-0.5 break-all font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :pinned_tool_manifest, :manifest_hash))}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Operation</dt>
                <dd class="mt-0.5 font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :reviewed_operation, :operation))}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">File</dt>
                <dd class="mt-0.5 break-all font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :reviewed_operation, :file_ref))}
                </dd>
              </div>
              <div class="sm:col-span-2">
                <dt class="text-slate-500">Content digest</dt>
                <dd class="mt-0.5 break-all font-medium text-slate-800">
                  {present_or_absent(nested_field(effect, :reviewed_operation, :content_digest))}
                </dd>
              </div>
            </dl>
          </section>

          <section
            :if={field(effect, :receipt)}
            id={effect_section_id(@id, effect, "receipt")}
            data-receipt-state={nested_field(effect, :receipt, :status)}
            class="mt-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-emerald-950"
          >
            <h4 class="text-xs font-semibold uppercase tracking-wide">Durable Receipt</h4>
            <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2">
              <div>
                <dt class="text-emerald-800">Receipt</dt>
                <dd class="mt-0.5 break-all font-medium">
                  {nested_field(effect, :receipt, :receipt_ref)}
                </dd>
              </div>
              <div>
                <dt class="text-emerald-800">State</dt>
                <dd class="mt-0.5 font-medium">
                  {display_status(nested_field(effect, :receipt, :status))}
                </dd>
              </div>
              <div>
                <dt class="text-emerald-800">Result artifact</dt>
                <dd class="mt-0.5 break-all font-medium">
                  {present_or_absent(nested_field(effect, :receipt, :result_artifact_ref))}
                </dd>
              </div>
              <div>
                <dt class="text-emerald-800">Cleanup</dt>
                <dd class="mt-0.5 font-medium">
                  {display_status(nested_field(effect, [:receipt, :cleanup], :status))}
                </dd>
              </div>
            </dl>
          </section>

          <section
            :if={is_nil(field(effect, :receipt))}
            id={effect_section_id(@id, effect, "receipt-absent")}
            class="mt-4 rounded border border-slate-200 bg-white p-3 text-sm text-slate-600"
          >
            No receipt is present in the current durable AppKit projection.
          </section>

          <section
            :if={field(effect, :cancelled?) == true}
            id={effect_section_id(@id, effect, "cancelled")}
            class="mt-4 rounded border border-slate-300 bg-slate-100 p-3 text-slate-900"
          >
            <h4 class="text-sm font-semibold">Effect cancelled</h4>
            <p class="mt-1 text-xs">
              Cancellation is confirmed only by the durable receipt shown above.
            </p>
          </section>

          <section
            :if={field(effect, :ambiguity)}
            id={effect_section_id(@id, effect, "ambiguity")}
            data-ambiguity-state={nested_field(effect, :ambiguity, :state)}
            class="mt-4 rounded border border-orange-300 bg-orange-50 p-3 text-orange-950"
          >
            <h4 class="text-sm font-semibold">Outcome requires reconciliation</h4>
            <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2">
              <div>
                <dt class="text-orange-800">State</dt>
                <dd class="mt-0.5 font-medium">
                  {display_status(nested_field(effect, :ambiguity, :state))}
                </dd>
              </div>
              <div>
                <dt class="text-orange-800">Effect retry</dt>
                <dd class="mt-0.5 font-medium">
                  {if nested_field(effect, :ambiguity, :effect_retry_allowed),
                    do: "admitted",
                    else: "prohibited"}
                </dd>
              </div>
            </dl>
          </section>

          <section
            :if={field(effect, :continuation)}
            id={effect_section_id(@id, effect, "continuation")}
            data-continuation-state={nested_field(effect, :continuation, :status)}
            class="mt-4 rounded border border-blue-200 bg-blue-50 p-3 text-blue-950"
          >
            <h4 class="text-sm font-semibold">Durable continuation</h4>
            <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2">
              <div>
                <dt class="text-blue-800">Continuation</dt>
                <dd class="mt-0.5 break-all font-medium">
                  {nested_field(effect, :continuation, :continuation_ref)}
                </dd>
              </div>
              <div>
                <dt class="text-blue-800">Status</dt>
                <dd class="mt-0.5 font-medium">
                  {display_status(nested_field(effect, :continuation, :status))}
                </dd>
              </div>
              <div>
                <dt class="text-blue-800">Owner</dt>
                <dd class="mt-0.5 break-all font-medium">
                  {present_or_absent(nested_field(effect, :continuation, :target_owner))}
                </dd>
              </div>
              <div>
                <dt class="text-blue-800">Operation</dt>
                <dd class="mt-0.5 break-all font-medium">
                  {nested_field(effect, :continuation, :target_operation)}
                </dd>
              </div>
            </dl>
          </section>

          <ol
            :if={timeline_entries(@timelines, effect) != []}
            id={effect_section_id(@id, effect, "timeline")}
            class="mt-4 grid gap-2 text-xs sm:grid-cols-2"
          >
            <li
              :for={entry <- timeline_entries(@timelines, effect)}
              id={timeline_entry_id(@id, effect, entry)}
              data-status={field(entry, :status)}
              class="rounded border border-slate-200 bg-white px-3 py-2"
            >
              <span class="font-semibold text-slate-900">
                {display_status(field(entry, :status))}
              </span>
              <span class="ml-2 text-slate-500">{field(entry, :event_kind)}</span>
              <div class="mt-1 break-all text-slate-500">{field(entry, :entry_hash)}</div>
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

  defp field(_attrs, _key), do: nil

  defp nested_field(effect, keys, key) when is_list(keys) do
    Enum.reduce(keys, effect, &field(&2, &1))
    |> field(key)
  end

  defp nested_field(effect, nested, key), do: effect |> field(nested) |> field(key)

  defp availability_state(effect) do
    case field(effect, :availability) do
      {state, _ref} when is_atom(state) -> state
      state when is_atom(state) -> state
      attrs when is_map(attrs) -> field(attrs, :state)
      _other -> :unavailable
    end
  end

  defp display_status("receipt_received"), do: "received"
  defp display_status(nil), do: "not present in durable readback"

  defp display_status(status) when is_atom(status),
    do: status |> Atom.to_string() |> display_status()

  defp display_status(status) when is_binary(status), do: String.replace(status, "_", " ")
  defp display_status(status), do: to_string(status)

  defp present_or_absent(value) when is_binary(value) and value != "", do: value
  defp present_or_absent(value) when is_integer(value), do: Integer.to_string(value)
  defp present_or_absent(value) when is_atom(value), do: Atom.to_string(value)
  defp present_or_absent(_value), do: "not present in durable readback"

  defp status_class(status) when status in ["completed", :completed] do
    "w-fit rounded border border-emerald-200 bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-800"
  end

  defp status_class(status) when status in ["failed", "cancelled", :failed, :cancelled] do
    "w-fit rounded border border-red-200 bg-red-50 px-2 py-1 text-xs font-semibold text-red-800"
  end

  defp status_class(status) when status in ["ambiguous", :outcome_unknown] do
    "w-fit rounded border border-orange-200 bg-orange-50 px-2 py-1 text-xs font-semibold text-orange-800"
  end

  defp status_class(_status) do
    "w-fit rounded border border-blue-200 bg-blue-50 px-2 py-1 text-xs font-semibold text-blue-800"
  end

  defp effect_dom_id(id, effect),
    do: "#{id}-effect-" <> stable_dom_token(field(effect, :effect_ref))

  defp effect_section_id(id, effect, section),
    do: effect_dom_id(id, effect) <> "-" <> section

  defp timeline_entry_id(id, effect, entry) do
    token =
      field(entry, :entry_hash) ||
        {field(entry, :sequence), field(entry, :event_kind)}

    effect_section_id(id, effect, "timeline-entry-" <> stable_dom_token(token))
  end

  defp stable_dom_token(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
