defmodule Synapse.Fixtures.EffectSurfaceBackend do
  @moduledoc """
  Deterministic EffectSurface backend for staged-live UI proofs.
  """

  @behaviour AppKit.EffectSurface

  alias AppKit.Core.{EffectTimelineDTO, GovernedEffectDTO}

  @timeline_statuses [
    "proposed",
    "authorized",
    "dispatched",
    "receipt_received",
    "reduced",
    "projected",
    "completed"
  ]

  @impl true
  def propose_effect(_context, %{effect_type: "diagnostic.probe"} = _attrs, _opts),
    do: {:error, :authority_denied}

  def propose_effect(_context, attrs, _opts) do
    attrs
    |> Map.merge(%{
      status: "completed",
      receipt_ref: "receipt://synapse/effects/diagnostic",
      authority_ref: "authority://synapse/effects/diagnostic",
      dispatch_ref: "dispatch://synapse/effects/diagnostic",
      metadata: metadata(attrs)
    })
    |> GovernedEffectDTO.new()
  end

  @impl true
  def get_effect(_context, effect_ref, _opts) do
    GovernedEffectDTO.new(%{
      effect_ref: effect_ref,
      effect_type: "diagnostic.echo",
      command_ref: "command://synapse/diagnostic/staged-live-diagnostic",
      tenant_ref: "tenant://default",
      actor_ref: "actor://synapse/operator",
      installation_ref: "installation://default",
      status: "completed",
      trace_ref: "trace://synapse/diagnostic/staged-live-diagnostic",
      authority_ref: "authority://synapse/effects/diagnostic",
      receipt_ref: "receipt://synapse/effects/diagnostic",
      dispatch_ref: "dispatch://synapse/effects/diagnostic",
      expected_version: 1,
      metadata: metadata(%{metadata: %{}, effect_ref: effect_ref})
    })
  end

  @impl true
  def list_effects(_context, _run_ref, _opts), do: {:ok, []}

  @impl true
  def get_effect_timeline(_context, effect_ref, _opts) do
    EffectTimelineDTO.new(%{
      effect_ref: effect_ref,
      trace_summary_hash: "sha256:synapse-diagnostic",
      entries:
        @timeline_statuses
        |> Enum.with_index(1)
        |> Enum.map(fn {status, sequence} ->
          %{
            "sequence" => sequence,
            "event_kind" => "effect_transition",
            "status" => status,
            "entry_hash" => "sha256:synapse-diagnostic-#{sequence}"
          }
        end),
      metadata: %{"source" => "synapse_fixture"}
    })
  end

  defp metadata(attrs) do
    attrs
    |> map_value(:metadata, %{})
    |> Map.merge(%{
      "diagnostic_result" => %{"status" => "ok", "summary" => "echo"},
      "evidence_refs" => ["evidence://synapse/effects/diagnostic"],
      "trace_summary_hash" => "sha256:synapse-diagnostic"
    })
  end

  defp map_value(attrs, key, default) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
