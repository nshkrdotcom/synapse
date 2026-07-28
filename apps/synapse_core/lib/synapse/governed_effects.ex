defmodule Synapse.GovernedEffects do
  @moduledoc """
  Product-safe reviewed-effect commands and durable readback through AppKit.

  Synapse handles only the product request and presentation seam. The durable
  effect owner, review owner, execution runtime, credentials, and workspace
  remain below AppKit.
  """

  alias AppKit.Core.GovernedEffectDTO
  alias AppKit.{EffectSurface, ReviewSurface}
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @operator_ref "actor:synapse:operator"

  @spec propose_reviewed_file_effect(struct(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def propose_reviewed_file_effect(context, proposal, opts \\ [])
      when is_map(proposal) and is_list(opts) do
    with {:ok, surface_opts} <- ProductBootstrap.effect_surface_options(opts),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.propose_effect(context, proposal, surface_opts) do
      {:ok, effect_view(effect)}
    end
  end

  @spec approve_reviewed_operation(String.t(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def approve_reviewed_operation(owner_execution_ref, attrs, opts \\ [])
      when is_binary(owner_execution_ref) and is_map(attrs) and is_list(opts) do
    with {:ok, effect_opts} <- ProductBootstrap.effect_surface_options(opts),
         {:ok, review_opts} <- ProductBootstrap.review_surface_options(opts),
         {:ok, context} <- product_context(opts, attrs),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.get_effect(context, owner_execution_ref, effect_opts),
         :ok <- ensure_pending_review(effect) do
      ReviewSurface.record_decision_by_id(
        context,
        effect.review.review_unit_id,
        %{
          decision: :accept,
          reason: string_value(attrs, :reason, "approved exact reviewed operation"),
          actor_ref: string_value(attrs, :actor_ref, @operator_ref),
          payload: exact_review_payload(effect)
        },
        review_opts
      )
    end
  end

  @spec begin_dispatch(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def begin_dispatch(owner_execution_ref, opts \\ [])
      when is_binary(owner_execution_ref) and is_list(opts) do
    with {:ok, surface_opts} <- ProductBootstrap.effect_surface_options(opts),
         {:ok, context} <- product_context(opts),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.get_effect(context, owner_execution_ref, surface_opts),
         {:ok, %GovernedEffectDTO{} = updated} <-
           EffectSurface.begin_dispatch(
             context,
             owner_execution_ref,
             %{expected_row_version: effect.row_version},
             surface_opts
           ) do
      {:ok, effect_view(updated)}
    end
  end

  @spec record_accepted(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def record_accepted(owner_execution_ref, attrs, opts \\ [])
      when is_binary(owner_execution_ref) and is_map(attrs) and is_list(opts) do
    with {:ok, surface_opts} <- ProductBootstrap.effect_surface_options(opts),
         {:ok, context} <- product_context(opts),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.get_effect(context, owner_execution_ref, surface_opts),
         command <-
           attrs
           |> take_values([:attempt_ref, :external_ref, :accepted_receipt_ref])
           |> Map.put(:expected_row_version, effect.row_version),
         {:ok, %GovernedEffectDTO{} = updated} <-
           EffectSurface.record_accepted(
             context,
             owner_execution_ref,
             command,
             surface_opts
           ) do
      {:ok, effect_view(updated)}
    end
  end

  @spec record_receipt(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def record_receipt(owner_execution_ref, attrs, opts \\ [])
      when is_binary(owner_execution_ref) and is_map(attrs) and is_list(opts) do
    with {:ok, surface_opts} <- ProductBootstrap.effect_surface_options(opts),
         {:ok, context} <- product_context(opts),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.get_effect(context, owner_execution_ref, surface_opts),
         command <-
           attrs
           |> take_values([
             :receipt_ref,
             :receipt_state,
             :ambiguity_state,
             :result_artifact_ref,
             :artifact_refs,
             :continuation_target,
             :cleanup
           ])
           |> Map.put(:expected_row_version, effect.row_version),
         {:ok, %GovernedEffectDTO{} = updated} <-
           EffectSurface.record_receipt(
             context,
             owner_execution_ref,
             command,
             surface_opts
           ) do
      {:ok, effect_view(updated)}
    end
  end

  @spec get_effect(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_effect(owner_execution_ref, opts \\ [])
      when is_binary(owner_execution_ref) and is_list(opts) do
    with {:ok, surface_opts} <- ProductBootstrap.effect_surface_options(opts),
         {:ok, context} <- product_context(opts),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.get_effect(context, owner_execution_ref, surface_opts) do
      {:ok, effect_view(effect)}
    end
  end

  @spec get_effect_by_idempotency(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_effect_by_idempotency(idempotency_key, opts \\ [])
      when is_binary(idempotency_key) and is_list(opts) do
    context_opts = Keyword.put(opts, :idempotency_key, idempotency_key)

    with {:ok, surface_opts} <- ProductBootstrap.effect_surface_options(context_opts),
         {:ok, context} <- product_context(context_opts),
         {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.get_effect_by_idempotency(
             context,
             idempotency_key,
             surface_opts
           ) do
      {:ok, effect_view(effect)}
    end
  end

  @spec effect_view(GovernedEffectDTO.t()) :: map()
  def effect_view(%GovernedEffectDTO{} = effect) do
    %{
      contract_version: effect.contract_version,
      effect_ref: effect.effect_ref,
      run_ref: effect.run_ref,
      turn_ref: effect.turn_ref,
      command_ref: effect.command_ref,
      decision_ref: effect.decision_ref,
      grant_ref: effect.grant_ref,
      target_ref: effect.target_ref,
      owner_execution_ref: effect.owner_execution_ref,
      status: effect.status,
      row_version: effect.row_version,
      attempt_ref: effect.attempt_ref,
      runtime_execution_ref: effect.runtime_execution_ref,
      external_ref: effect.external_ref,
      result_artifact_ref: effect.result_artifact_ref,
      pinned_tool_manifest: effect.pinned_tool_manifest,
      reviewed_operation: effect.reviewed_operation,
      review: nested_view(effect.review),
      receipt: nested_view(effect.receipt),
      ambiguity: nested_view(effect.ambiguity),
      continuation: nested_view(effect.continuation)
    }
  end

  defp product_context(opts, attrs \\ %{}) do
    config = Config.load(opts)
    actor_ref = string_value(attrs, :actor_ref, nil)

    context_opts =
      if is_binary(actor_ref) do
        Keyword.put(opts, :actor_ref, %{id: actor_ref, kind: :human})
      else
        opts
      end

    with {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(
             Keyword.put(context_opts, :bootstrap_mode, :disabled)
           ) do
      {:ok, PlatformContext.product_context(config, bootstrap.installation_ref, context_opts)}
    end
  end

  defp ensure_pending_review(%GovernedEffectDTO{review: %{status: status}})
       when status in ["pending", "in_review"],
       do: :ok

  defp ensure_pending_review(_effect), do: {:error, :effect_review_not_pending}

  defp exact_review_payload(effect) do
    %{
      "effect_ref" => effect.effect_ref,
      "pinned_tool_manifest" => effect.pinned_tool_manifest,
      "reviewed_operation" => effect.reviewed_operation
    }
  end

  defp nested_view(nil), do: nil
  defp nested_view(%_{} = value), do: value |> Map.from_struct() |> nested_view()

  defp nested_view(%{} = value) do
    Map.new(value, fn {key, nested} -> {key, nested_view(nested)} end)
  end

  defp nested_view(values) when is_list(values), do: Enum.map(values, &nested_view/1)
  defp nested_view(value), do: value

  defp take_values(attrs, keys) do
    keys
    |> Enum.reduce(%{}, fn key, selected ->
      case map_value(attrs, key) do
        nil -> selected
        value -> Map.put(selected, key, value)
      end
    end)
  end

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
