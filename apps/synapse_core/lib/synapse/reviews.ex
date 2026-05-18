defmodule Synapse.Reviews do
  @moduledoc """
  Product-safe review queue, detail, and decision commands.
  """

  alias AppKit.Core.{DecisionRef, PageRequest}
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @default_review_surface Synapse.Fixtures.ReviewSurface
  @allowed_decisions %{
    "accept" => :accept,
    "reject" => :reject,
    "waive" => :waive,
    "expired" => :expired,
    "escalate" => :escalate
  }

  @spec list_pending(keyword()) :: {:ok, map()} | {:error, term()}
  def list_pending(opts \\ []) do
    context = product_context(opts)

    with {:ok, page_request} <- PageRequest.new(%{limit: Keyword.get(opts, :limit, 25)}),
         {:ok, page} <- review_surface(opts).list_pending(context, page_request, opts) do
      {:ok,
       %{
         entries: Enum.map(page.entries, &view_model/1),
         total_count: page.total_count || length(page.entries),
         has_more: page.has_more == true,
         source: Map.get(page.metadata, :source, :unknown)
       }}
    end
  end

  @spec get_review(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_review(decision_id, opts \\ []) when is_binary(decision_id) do
    context = product_context(opts)

    with {:ok, decision_ref} <- decision_ref(decision_id),
         {:ok, review} <- review_surface(opts).get_review(context, decision_ref, opts) do
      {:ok, view_model(review)}
    end
  end

  @spec record_decision(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def record_decision(decision_id, attrs, opts \\ [])
      when is_binary(decision_id) and is_map(attrs) and is_list(opts) do
    context = product_context(opts)

    with {:ok, decision} <- normalize_decision(attrs),
         {:ok, decision_ref} <- decision_ref(decision_id) do
      review_surface(opts).record_decision(
        context,
        decision_ref,
        decision_attrs(attrs, decision),
        opts
      )
    end
  end

  defp view_model(review) when is_map(review) do
    %{
      id: string_value(review, :id, "fixture-review"),
      decision_id: string_value(review, :decision_id, "decision://fixture/review"),
      decision_kind: string_value(review, :decision_kind, "operator_review"),
      run_ref: string_value(review, :run_ref, "run://fixture/phase-3"),
      subject_ref: string_value(review, :subject_ref, "subject://fixture/phase-3"),
      title: string_value(review, :title, "Fixture review"),
      status: map_value(review, :status) || :pending,
      authority_state: map_value(review, :authority_state) || :authorized,
      reviewer_role: string_value(review, :reviewer_role, "operator"),
      reason_codes: map_value(review, :reason_codes) || [],
      evidence_refs: map_value(review, :evidence_refs) || [],
      context_pack_ref: string_value(review, :context_pack_ref, "context-pack://fixture/phase-3"),
      memory_posture: map_value(review, :memory_posture) || :disabled,
      tool_posture: map_value(review, :tool_posture) || :fixture_projected,
      stale?: map_value(review, :stale?) == true,
      denied?: map_value(review, :denied?) == true
    }
  end

  defp normalize_decision(attrs) do
    case map_value(attrs, :decision) do
      decision
      when is_atom(decision) and decision in [:accept, :reject, :waive, :expired, :escalate] ->
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
    %{
      decision: decision,
      reason: string_value(attrs, :reason, "operator_decision"),
      actor_ref: string_value(attrs, :actor_ref, "actor:synapse:operator")
    }
  end

  defp decision_ref(decision_id) do
    DecisionRef.new(%{
      id: normalize_decision_id(decision_id),
      decision_kind: "operator_review"
    })
  end

  defp normalize_decision_id("decision://" <> _rest = decision_id), do: decision_id
  defp normalize_decision_id(id), do: "decision://fixture/#{id}"

  defp product_context(opts) do
    config = Config.load(opts)

    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    PlatformContext.product_context(config, bootstrap.installation_ref, opts)
  end

  defp review_surface(opts), do: Keyword.get(opts, :review_surface, @default_review_surface)

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
