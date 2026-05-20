defmodule Synapse.GovernedEffects do
  @moduledoc """
  Product-safe governed-effect helpers for the staged-live diagnostic path.
  """

  alias AppKit.Core.{EffectTimelineDTO, GovernedEffectDTO}
  alias AppKit.EffectSurface
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @actor_ref "actor://synapse/operator"

  @spec propose_diagnostic_run(struct(), map(), String.t(), atom(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def propose_diagnostic_run(context, attrs, run_id, diagnostic_lane, opts)
      when is_map(attrs) and is_binary(run_id) and is_atom(diagnostic_lane) and is_list(opts) do
    effect_attrs = diagnostic_effect_attrs(context, attrs, run_id, diagnostic_lane)

    with {:ok, %GovernedEffectDTO{} = effect} <-
           EffectSurface.propose_effect(context, effect_attrs, opts) do
      {:ok, effect_view(effect)}
    end
  end

  @spec get_effect_timeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_effect_timeline(effect_ref, opts \\ []) when is_binary(effect_ref) and is_list(opts) do
    config = Config.load(opts)

    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    context = PlatformContext.product_context(config, bootstrap.installation_ref, opts)

    with {:ok, %EffectTimelineDTO{} = timeline} <-
           EffectSurface.get_effect_timeline(context, effect_ref, opts) do
      {:ok, timeline_view(timeline)}
    end
  end

  @spec effect_view(GovernedEffectDTO.t()) :: map()
  def effect_view(%GovernedEffectDTO{} = effect) do
    metadata = effect.metadata || %{}

    %{
      effect_ref: effect.effect_ref,
      effect_type: effect.effect_type,
      command_ref: effect.command_ref,
      tenant_ref: effect.tenant_ref,
      actor_ref: effect.actor_ref,
      installation_ref: effect.installation_ref,
      status: effect.status,
      trace_ref: effect.trace_ref,
      authority_ref: effect.authority_ref,
      receipt_ref: effect.receipt_ref,
      dispatch_ref: effect.dispatch_ref,
      expected_version: effect.expected_version,
      run_ref: Map.get(metadata, "run_ref"),
      trace_summary_hash: Map.get(metadata, "trace_summary_hash"),
      evidence_refs: evidence_refs(effect),
      governed_effect_refs: governed_effect_refs(effect),
      metadata: metadata
    }
  end

  @spec timeline_view(EffectTimelineDTO.t()) :: map()
  def timeline_view(%EffectTimelineDTO{} = timeline) do
    %{
      effect_ref: timeline.effect_ref,
      trace_summary_hash: timeline.trace_summary_hash,
      entries: Enum.map(timeline.entries, &timeline_entry/1),
      metadata: timeline.metadata || %{}
    }
  end

  defp diagnostic_effect_attrs(context, attrs, run_id, diagnostic_lane) do
    lane_name = Atom.to_string(diagnostic_lane)

    %{
      effect_ref: "effect://synapse/#{run_id}/#{lane_name}",
      effect_type: "diagnostic.#{lane_name}",
      command_ref: "command://synapse/diagnostic/#{run_id}",
      tenant_ref: tenant_ref(context),
      actor_ref: @actor_ref,
      installation_ref: installation_ref(context),
      status: "proposed",
      trace_ref: context.trace_id,
      expected_version: 1,
      metadata: %{
        "diagnostic_lane" => lane_name,
        "goal_summary" => string_value(attrs, :goal_summary, "No goal summary provided"),
        "product_slug" => "synapse",
        "run_ref" => "run://live-stack/#{run_id}",
        "title" => string_value(attrs, :title, "Untitled agent run")
      }
    }
  end

  defp governed_effect_refs(%GovernedEffectDTO{} = effect) do
    %{
      "effect_ref" => effect.effect_ref,
      "command_ref" => effect.command_ref,
      "trace_ref" => effect.trace_ref,
      "authority_ref" => effect.authority_ref,
      "receipt_ref" => effect.receipt_ref,
      "dispatch_ref" => effect.dispatch_ref
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp evidence_refs(%GovernedEffectDTO{} = effect) do
    effect.metadata
    |> case do
      %{} = metadata -> Map.get(metadata, "evidence_refs", [])
      _other -> []
    end
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  defp timeline_entry(entry) when is_map(entry) do
    %{
      sequence: integer_value(entry, "sequence"),
      event_kind: string_value(entry, "event_kind", "effect_transition"),
      status: string_value(entry, "status", "unknown"),
      entry_hash: string_value(entry, "entry_hash", nil)
    }
  end

  defp timeline_entry(_entry) do
    %{sequence: nil, event_kind: "effect_transition", status: "unknown", entry_hash: nil}
  end

  defp tenant_ref(%{tenant_ref: %{id: id}}) when is_binary(id), do: "tenant://#{id}"
  defp tenant_ref(_context), do: "tenant://default"

  defp installation_ref(%{installation_ref: %{id: id}}) when is_binary(id),
    do: "installation://#{id}"

  defp installation_ref(_context), do: "installation://default"

  defp integer_value(attrs, key) do
    case map_value(attrs, key) do
      value when is_integer(value) -> value
      _other -> nil
    end
  end

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _other -> default
    end
  end

  defp map_value(attrs, key) when is_atom(key),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp map_value(attrs, key) when is_binary(key), do: Map.get(attrs, key)
end
