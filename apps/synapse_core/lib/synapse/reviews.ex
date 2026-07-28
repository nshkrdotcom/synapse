defmodule Synapse.Reviews do
  @moduledoc """
  Product-safe review queue, detail, and decision commands.
  """

  alias AppKit.Core.{DecisionRef, PageRequest}
  alias AppKit.ReviewSurface
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @allowed_decisions %{
    "accept" => :accept,
    "reject" => :reject,
    "waive" => :waive,
    "escalate" => :escalate
  }

  @spec list_pending(keyword()) :: {:ok, map()} | {:error, term()}
  def list_pending(opts \\ []) do
    context = product_context(opts)

    with {:ok, review_opts} <- ProductBootstrap.review_surface_options(opts),
         {:ok, page_request} <- PageRequest.new(%{limit: Keyword.get(opts, :limit, 25)}),
         {:ok, page} <- ReviewSurface.list_pending(context, page_request, review_opts) do
      {:ok,
       %{
         entries: Enum.map(page.entries, &view_model/1),
         total_count: page.total_count || length(page.entries),
         has_more: page.has_more == true,
         source: map_value(page.metadata || %{}, :source) || :app_kit
       }}
    end
  end

  @spec get_review(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_review(decision_id, opts \\ []) when is_binary(decision_id) do
    context = product_context(opts)

    with {:ok, review_opts} <- ProductBootstrap.review_surface_options(opts),
         {:ok, decision_ref} <- decision_ref(decision_id),
         {:ok, review} <- ReviewSurface.get_review(context, decision_ref, review_opts) do
      {:ok, view_model(review)}
    end
  end

  @spec record_decision(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def record_decision(decision_id, attrs, opts \\ [])
      when is_binary(decision_id) and is_map(attrs) and is_list(opts) do
    context = product_context(opts)

    with {:ok, review_opts} <- ProductBootstrap.review_surface_options(opts),
         {:ok, decision} <- normalize_decision(attrs),
         {:ok, decision_ref} <- decision_ref(decision_id) do
      ReviewSurface.record_decision(
        context,
        decision_ref,
        decision_attrs(attrs, decision),
        review_opts
      )
    end
  end

  defp view_model(review) when is_map(review) do
    decision_ref = map_value(review, :decision_ref) || %{}
    subject_ref = map_value(review, :subject_ref) || map_value(decision_ref, :subject_ref) || %{}
    payload = map_value(review, :payload) || %{}
    work_object = map_value(payload, :work_object) || %{}
    run = map_value(payload, :run) || %{}
    reviewer = map_value(payload, :reviewer_actor) || %{}
    gate = map_value(payload, :gate_status) || %{}
    decision_id = first_string([decision_ref, review], [:id, :decision_id])

    %{
      id: decision_id,
      decision_id: decision_id,
      decision_kind: first_string([decision_ref, review], [:decision_kind]) || "operator_review",
      run_ref: first_string([review, run], [:run_ref, :id]),
      subject_ref: first_string([subject_ref, review], [:id, :subject_ref]),
      title:
        first_string([review, work_object], [:summary, :title]) ||
          "Review #{decision_id || "unavailable"}",
      status: map_value(review, :status) || :unknown,
      authority_state: authority_state(review, gate),
      reviewer_role:
        first_string([review, reviewer], [:reviewer_role, :kind, :role]) || "operator",
      reason_codes: list_value(review, payload, :reason_codes),
      evidence_refs: evidence_refs(review, payload),
      context_pack_ref: first_string([review, payload], [:context_pack_ref]),
      memory_posture: map_value(review, :memory_posture) || :not_projected,
      tool_posture: map_value(review, :tool_posture) || :reviewed_effect,
      approval_payload: approval_payload(payload),
      stale?: map_value(review, :stale?) == true,
      denied?: denied?(review, gate)
    }
  end

  defp normalize_decision(attrs) do
    case map_value(attrs, :decision) do
      decision
      when is_atom(decision) and decision in [:accept, :reject, :waive, :escalate] ->
        {:ok, decision}

      decision when is_binary(decision) ->
        case Map.fetch(@allowed_decisions, decision) do
          {:ok, decision} -> {:ok, decision}
          :error -> {:error, :invalid_review_decision}
        end

      _other ->
        {:error, :invalid_review_decision}
    end
  end

  defp decision_attrs(attrs, decision) do
    base = %{
      decision: decision,
      reason: string_value(attrs, :reason, "operator_decision"),
      actor_ref: string_value(attrs, :actor_ref, "actor:synapse:operator")
    }

    case map_value(attrs, :payload) do
      payload when is_map(payload) -> Map.put(base, :payload, payload)
      _other -> base
    end
  end

  defp decision_ref(decision_id) do
    DecisionRef.new(%{
      id: decision_id,
      decision_kind: "operator_review"
    })
  end

  defp product_context(opts) do
    config = Config.load(opts)

    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    PlatformContext.product_context(config, bootstrap.installation_ref, opts)
  end

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _other -> default
    end
  end

  defp first_string(sources, keys) do
    Enum.find_value(sources, fn source ->
      Enum.find_value(keys, fn key -> string_value(source, key, nil) end)
    end)
  end

  defp authority_state(review, gate) do
    map_value(review, :authority_state) ||
      cond do
        map_value(gate, :release_ready?) == true -> :authorized
        denied?(review, gate) -> :denied
        true -> :pending
      end
  end

  defp denied?(review, gate) do
    map_value(review, :denied?) == true or
      map_value(review, :status) in [:rejected, "rejected", :denied, "denied"] or
      map_value(gate, :denied?) == true
  end

  defp list_value(review, payload, key) do
    case map_value(review, key) || map_value(payload, key) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp evidence_refs(review, payload) do
    direct = list_value(review, payload, :evidence_refs)

    if direct == [] do
      payload
      |> map_value(:evidence_items)
      |> List.wrap()
      |> Enum.map(&first_string([&1], [:evidence_ref, :receipt_ref, :id]))
      |> Enum.filter(&is_binary/1)
    else
      direct
    end
  end

  defp approval_payload(payload) do
    candidate =
      map_value(payload, :approval_payload) ||
        map_value(payload, :effect_approval_payload)

    case candidate do
      value when is_map(value) ->
        effect_ref = map_value(value, :effect_ref)
        manifest = map_value(value, :pinned_tool_manifest)
        operation = map_value(value, :reviewed_operation)

        if is_binary(effect_ref) and is_map(manifest) and is_map(operation) do
          %{
            "effect_ref" => effect_ref,
            "pinned_tool_manifest" => manifest,
            "reviewed_operation" => operation
          }
        end

      _other ->
        nil
    end
  end

  defp map_value(nil, _key), do: nil
  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
