defmodule Synapse.Reviews do
  @moduledoc """
  Product-safe durable review queue, detail, and decision commands.

  The AppKit review projection is the only source of review truth. Synapse
  validates the owner projection into a closed product view and binds decisions
  to the exact effect material returned by that projection.
  """

  alias AppKit.Core.{DecisionRef, PageRequest}
  alias AppKit.ReviewSurface
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @review_statuses %{
    "pending" => :pending,
    "in_review" => :in_review,
    "accepted" => :accepted,
    "rejected" => :rejected,
    "waived" => :waived,
    "escalated" => :escalated,
    "expired" => :expired,
    "cancelled" => :cancelled
  }
  @allowed_decisions %{
    "accept" => :accept,
    "reject" => :reject,
    "waive" => :waive,
    "escalate" => :escalate
  }
  @open_statuses [:pending, :in_review, :escalated]
  @forbidden_projection_keys MapSet.new(~w(
                                 api_key authorization content credential credentials env
                                 environment home password provider_key secret secrets token
                                 workspace_root
                               ))

  @spec list_pending(keyword()) :: {:ok, map()} | {:error, term()}
  def list_pending(opts \\ []) when is_list(opts) do
    with {:ok, context} <- product_context(opts),
         {:ok, review_opts} <- ProductBootstrap.review_surface_options(opts),
         {:ok, page_request} <- PageRequest.new(%{limit: Keyword.get(opts, :limit, 25)}),
         {:ok, page} <- ReviewSurface.list_pending(context, page_request, review_opts),
         {:ok, entries} <- view_models(page.entries) do
      {:ok,
       %{
         entries: entries,
         total_count: page.total_count || length(entries),
         has_more: page.has_more == true,
         source: map_value(page.metadata || %{}, :source) || :app_kit,
         availability: :available
       }}
    end
  end

  @spec get_review(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_review(decision_id, opts \\ [])
      when is_binary(decision_id) and is_list(opts) do
    with :ok <- present_ref(decision_id, :invalid_review_ref),
         {:ok, context} <- product_context(opts),
         {:ok, review_opts} <- ProductBootstrap.review_surface_options(opts),
         {:ok, decision_ref} <- decision_ref(decision_id),
         {:ok, review} <- ReviewSurface.get_review(context, decision_ref, review_opts) do
      view_model(review)
    end
  end

  @spec record_decision(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def record_decision(decision_id, attrs, opts \\ [])

  def record_decision(decision_id, attrs, opts)
      when is_binary(decision_id) and is_map(attrs) and is_list(opts) do
    with {:ok, decision} <- normalize_decision(attrs),
         {:ok, review} <- get_review(decision_id, opts),
         :ok <- ensure_decision_allowed(review, decision),
         command_opts <- decision_context_options(opts, review, decision, attrs),
         {:ok, context} <- product_context(command_opts),
         {:ok, review_opts} <- ProductBootstrap.review_surface_options(command_opts),
         {:ok, decision_ref} <- decision_ref(decision_id) do
      ReviewSurface.record_decision(
        context,
        decision_ref,
        decision_attrs(attrs, decision, review),
        review_opts
      )
    end
  end

  def record_decision(_decision_id, _attrs, _opts),
    do: {:error, :invalid_review_decision_command}

  defp view_models(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case view_model(entry) do
        {:ok, view} -> {:cont, {:ok, [view | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, views} -> {:ok, Enum.reverse(views)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp view_models(_entries), do: {:error, :invalid_durable_review_page}

  defp view_model(review) when is_map(review) do
    decision_ref = map_value(review, :decision_ref) || %{}
    subject_ref = map_value(review, :subject_ref) || map_value(decision_ref, :subject_ref) || %{}
    payload = map_value(review, :payload) || %{}
    work_object = map_value(payload, :work_object) || %{}
    run = map_value(payload, :run) || %{}
    reviewer = map_value(payload, :reviewer_actor) || %{}
    gate = map_value(payload, :gate_status) || %{}
    review_unit = map_value(payload, :review_unit) || %{}
    decision_id = first_string([decision_ref, review], [:id, :decision_id])
    decision_kind = first_string([decision_ref, review, payload], [:decision_kind, :review_kind])
    title = first_string([review, work_object], [:summary, :title])
    subject_id = first_string([subject_ref, review], [:id, :subject_ref])
    status_value = map_value(review, :status) || map_value(review_unit, :status)

    with :ok <- present_ref(decision_id, :invalid_durable_review_projection),
         :ok <- present_string(decision_kind, :invalid_durable_review_projection),
         :ok <- present_ref(subject_id, :invalid_durable_review_projection),
         :ok <- present_string(title, :invalid_durable_review_projection),
         {:ok, status} <- normalize_status(status_value),
         {:ok, approval_payload} <- approval_payload(payload),
         {:ok, lookup} <- effect_lookup(review, payload, work_object, review_unit) do
      stale? = map_value(review, :stale?) == true
      denied? = denied?(review, gate, status)

      {:ok,
       %{
         id: decision_id,
         decision_id: decision_id,
         decision_kind: decision_kind,
         run_ref: first_string([review, run, review_unit], [:run_ref, :id, :run_id]),
         subject_ref: subject_id,
         title: title,
         status: status,
         authority_state: authority_state(review, gate, status),
         reviewer_role: first_string([review, reviewer], [:reviewer_role, :kind, :role]),
         reason_codes: string_list(review, payload, :reason_codes),
         evidence_refs: evidence_refs(review, payload),
         context_pack_ref: first_string([review, payload], [:context_pack_ref]),
         memory_posture: map_value(review, :memory_posture),
         tool_posture: map_value(review, :tool_posture),
         required_by: map_value(review, :required_by),
         row_version: positive_integer(review, review_unit, :row_version),
         approval_payload: approval_payload,
         effect_ref: approval_payload && approval_payload["effect_ref"],
         effect_lookup: lookup,
         stale?: stale?,
         denied?: denied?,
         allowed_decisions: allowed_decisions(status, stale?, denied?),
         availability: :available
       }}
    end
  end

  defp view_model(_review), do: {:error, :invalid_durable_review_projection}

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

  defp decision_attrs(attrs, decision, review) do
    base = %{
      decision: decision,
      reason: string_value(attrs, :reason, "operator_decision"),
      actor_ref: string_value(attrs, :actor_ref, "actor:synapse:operator")
    }

    case review.approval_payload do
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

    with {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled)) do
      {:ok, PlatformContext.product_context(config, bootstrap.installation_ref, opts)}
    end
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

  defp authority_state(review, gate, status) do
    case map_value(review, :authority_state) do
      value when value in [:authorized, "authorized"] -> :authorized
      value when value in [:denied, "denied"] -> :denied
      value when value in [:operator_required, "operator_required"] -> :operator_required
      value when value in [:expired, "expired"] -> :expired
      value when value in [:cancelled, "cancelled"] -> :cancelled
      _other -> authority_from_durable_state(gate, status)
    end
  end

  defp authority_from_durable_state(gate, status) do
    cond do
      map_value(gate, :release_ready?) == true -> :authorized
      map_value(gate, :denied?) == true -> :denied
      status in [:accepted, :waived] -> :authorized
      status == :rejected -> :denied
      status == :escalated -> :operator_required
      status == :expired -> :expired
      status == :cancelled -> :cancelled
      true -> :pending
    end
  end

  defp denied?(review, gate, status) do
    map_value(review, :denied?) == true or
      status == :rejected or
      map_value(gate, :denied?) == true
  end

  defp string_list(review, payload, key) do
    case map_value(review, key) || map_value(payload, key) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _other -> []
    end
  end

  defp evidence_refs(review, payload) do
    direct = string_list(review, payload, :evidence_refs)

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
          approval = %{
            "effect_ref" => effect_ref,
            "pinned_tool_manifest" => manifest,
            "reviewed_operation" => operation
          }

          if safe_projection?(approval),
            do: {:ok, approval},
            else: {:error, :invalid_durable_review_effect_payload}
        else
          {:error, :invalid_durable_review_effect_payload}
        end

      nil ->
        {:ok, nil}

      _other ->
        {:error, :invalid_durable_review_effect_payload}
    end
  end

  defp effect_lookup(review, payload, work_object, review_unit) do
    sources = [review, payload, work_object, review_unit, map_value(payload, :approval_payload)]

    owner_ref =
      first_string(sources, [
        :owner_execution_ref,
        :effect_execution_ref
      ])

    idempotency_key =
      first_string(sources, [
        :effect_idempotency_key,
        :idempotency_key
      ])

    cond do
      effect_owner_ref?(owner_ref) -> {:ok, {:owner_execution_ref, owner_ref}}
      present_binary?(idempotency_key) -> {:ok, {:idempotency_key, idempotency_key}}
      is_nil(owner_ref) and is_nil(idempotency_key) -> {:ok, nil}
      true -> {:error, :invalid_durable_effect_lookup}
    end
  end

  defp normalize_status(status) when is_atom(status),
    do: normalize_status(Atom.to_string(status))

  defp normalize_status(status) when is_binary(status) do
    case Map.fetch(@review_statuses, status) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, :invalid_durable_review_status}
    end
  end

  defp normalize_status(_status), do: {:error, :invalid_durable_review_status}

  defp allowed_decisions(status, false, false) when status in @open_statuses,
    do: [:accept, :reject, :waive, :escalate]

  defp allowed_decisions(_status, _stale?, _denied?), do: []

  defp ensure_decision_allowed(%{allowed_decisions: decisions}, decision) do
    if decision in decisions, do: :ok, else: {:error, :review_decision_not_allowed}
  end

  defp decision_context_options(opts, review, decision, attrs) do
    actor_ref = string_value(attrs, :actor_ref, "actor:synapse:operator")

    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({
          review.decision_id,
          review.row_version,
          decision,
          actor_ref,
          review.approval_payload
        })
      )
      |> Base.url_encode64(padding: false)

    opts
    |> Keyword.put(:actor_ref, %{id: actor_ref, kind: :human})
    |> Keyword.put_new(:idempotency_key, "synapse:review:#{digest}")
    |> Keyword.put_new(:request_id, "request://synapse/review/#{digest}")
  end

  defp positive_integer(primary, secondary, key) do
    case map_value(primary, key) || map_value(secondary, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> nil
    end
  end

  defp present_ref(value, error) do
    if present_binary?(value), do: :ok, else: {:error, error}
  end

  defp present_string(value, error), do: present_ref(value, error)

  defp effect_owner_ref?("effect-execution://" <> id), do: id != ""
  defp effect_owner_ref?(_value), do: false

  defp present_binary?(value), do: is_binary(value) and String.trim(value) != ""

  defp safe_projection?(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: true

  defp safe_projection?(nil), do: true
  defp safe_projection?(value) when is_atom(value), do: true
  defp safe_projection?(values) when is_list(values), do: Enum.all?(values, &safe_projection?/1)

  defp safe_projection?(attrs) when is_map(attrs) do
    Enum.all?(attrs, fn {key, value} ->
      safe_projection_key?(key) and safe_projection?(value)
    end)
  end

  defp safe_projection?(_value), do: false

  defp safe_projection_key?(key) when is_atom(key),
    do: not MapSet.member?(@forbidden_projection_keys, Atom.to_string(key))

  defp safe_projection_key?(key) when is_binary(key),
    do: not MapSet.member?(@forbidden_projection_keys, key)

  defp safe_projection_key?(_key), do: false

  defp map_value(nil, _key), do: nil
  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
