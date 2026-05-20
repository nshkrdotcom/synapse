defmodule Synapse.GovernedEffectsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.EffectTimelineDTO
  alias Synapse.GovernedEffects

  defmodule TimelineBackend do
    @behaviour AppKit.EffectSurface

    def propose_effect(_context, _attrs, _opts), do: {:error, :not_used}
    def get_effect(_context, _effect_ref, _opts), do: {:error, :not_used}
    def list_effects(_context, _run_ref, _opts), do: {:error, :not_used}

    def get_effect_timeline(_context, effect_ref, _opts) do
      EffectTimelineDTO.new(%{
        effect_ref: effect_ref,
        trace_summary_hash: "sha256:synapse-diagnostic",
        entries:
          Enum.with_index(
            [
              "proposed",
              "authorized",
              "dispatched",
              "receipt_received",
              "reduced",
              "projected",
              "completed"
            ],
            1
          )
          |> Enum.map(fn {status, sequence} ->
            %{
              "sequence" => sequence,
              "event_kind" => "effect_transition",
              "status" => status,
              "entry_hash" => "sha256:synapse-diagnostic-#{sequence}"
            }
          end),
        metadata: %{"source" => "test"}
      })
    end
  end

  defmodule DeniedTimelineBackend do
    @behaviour AppKit.EffectSurface

    def propose_effect(_context, _attrs, _opts), do: {:error, :not_used}
    def get_effect(_context, _effect_ref, _opts), do: {:error, :not_used}
    def list_effects(_context, _run_ref, _opts), do: {:error, :not_used}

    def get_effect_timeline(_context, effect_ref, _opts) do
      EffectTimelineDTO.new(%{
        effect_ref: effect_ref,
        entries: [
          %{
            "sequence" => 1,
            "event_kind" => "effect_transition",
            "status" => "denied",
            "entry_hash" => "sha256:synapse-denied"
          }
        ],
        metadata: %{"source" => "test"}
      })
    end
  end

  test "returns product-safe timeline for a staged-live effect" do
    assert {:ok, timeline} =
             GovernedEffects.get_effect_timeline(
               "effect://synapse/diagnostic-live/echo",
               effect_surface_adapter: TimelineBackend
             )

    assert timeline.effect_ref == "effect://synapse/diagnostic-live/echo"
    assert timeline.trace_summary_hash == "sha256:synapse-diagnostic"

    assert Enum.map(timeline.entries, & &1.status) == [
             "proposed",
             "authorized",
             "dispatched",
             "receipt_received",
             "reduced",
             "projected",
             "completed"
           ]

    refute Enum.any?(timeline.entries, &Map.has_key?(&1, :body))
  end

  test "denied timelines keep explicit denial status" do
    assert {:ok, timeline} =
             GovernedEffects.get_effect_timeline(
               "effect://synapse/diagnostic-denied/echo",
               effect_surface_adapter: DeniedTimelineBackend
             )

    assert [%{status: "denied"}] = timeline.entries
  end
end
