defmodule Synapse.Evidence do
  @moduledoc """
  Product-safe evidence, receipt, replay, and operations projections.
  """

  alias AppKit.Core.{
    EvidenceProjection,
    LowerReceiptSummary,
    RuntimeEventSummary,
    RuntimeFactsProjection
  }

  alias AppKit.Core.RuntimeSurface.RuntimeStatusSnapshot
  alias AppKit.ReplaySurface

  @evidence_items [
    %{
      id: "run-start",
      evidence_ref: "evidence://synapse/run-start",
      evidence_kind: "run_start",
      status: "available",
      content_ref: "content://synapse/evidence/run-start",
      receipt_ref: "receipt://synapse/run-start",
      run_ref: "run://fixture/phase-3"
    },
    %{
      id: "review-decision",
      evidence_ref: "evidence://synapse/review-decision",
      evidence_kind: "review_decision",
      status: "available",
      content_ref: "content://synapse/evidence/review-decision",
      receipt_ref: "receipt://synapse/review-decision",
      run_ref: "run://fixture/phase-3"
    },
    %{
      id: "missing-live-receipt",
      evidence_ref: "evidence://synapse/missing-live-receipt",
      evidence_kind: "live_effect",
      status: "missing",
      content_ref: nil,
      receipt_ref: nil,
      run_ref: "run://fixture/phase-3",
      missing_reason: :live_backend_not_proven
    }
  ]

  @spec list_evidence(keyword()) :: [map()]
  def list_evidence(opts \\ []) do
    opts
    |> evidence_items()
    |> Enum.map(&evidence_view!/1)
  end

  @spec get_evidence(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_evidence(id_or_ref, opts \\ []) when is_binary(id_or_ref) do
    case Enum.find(evidence_items(opts), &(&1.id == id_or_ref or &1.evidence_ref == id_or_ref)) do
      nil -> {:error, :evidence_not_found}
      item -> {:ok, evidence_view!(item)}
    end
  end

  @spec get_receipt(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_receipt(receipt_ref, opts \\ []) when is_binary(receipt_ref) do
    case Enum.find(evidence_items(opts), &(&1.receipt_ref == receipt_ref)) do
      nil -> {:error, :receipt_not_found}
      item -> {:ok, receipt_view!(item)}
    end
  end

  @spec replay_bundle(keyword()) :: map()
  def replay_bundle(_opts \\ []) do
    {:ok, bundle} =
      ReplaySurface.bundle_projection(%{
        tenant_ref: "tenant://default",
        authority_ref: "authority://synapse/default",
        installation_ref: "installation://default",
        idempotency_key: "synapse:replay:phase-8",
        trace_ref: "replay-bundle://synapse/phase-8",
        source_trace_ref: "trace://fixture/source/phase-3",
        replay_trace_ref: "trace://fixture/replay/phase-8",
        divergence_refs: ["replay-divergence://synapse/phase-8/memory"],
        decision_class: :diverged,
        cost_class: :replay,
        operator_action: "review_required",
        release_manifest_ref: "release://synapse/catalog"
      })

    {:ok, divergence} =
      ReplaySurface.divergence_projection(%{
        divergence_ref: "replay-divergence://synapse/phase-8/memory",
        phase: :memory_access,
        severity: :warn,
        redacted_excerpt_class: "refs_only",
        remediation_class: :review,
        source_span_ref: "span://fixture/source/memory",
        replay_span_ref: "span://fixture/replay/memory"
      })

    %{
      status: :fixture_backed,
      bundle: bundle,
      divergences: [divergence],
      replay_links: [
        %{
          label: "Source trace",
          ref: bundle.source_trace_ref,
          status: :fixture_backed
        },
        %{
          label: "Replay trace",
          ref: bundle.replay_trace_ref,
          status: :fixture_backed
        }
      ]
    }
  end

  @spec operations(keyword()) :: map()
  def operations(_opts \\ []) do
    {:ok, snapshot} =
      RuntimeStatusSnapshot.new(%{
        tenant_ref: "tenant://default",
        program_ref: "program://synapse",
        health: %{
          appkit_surfaces: "ok",
          projection_lag: "fixture",
          lower_invocation_errors: "none_projected",
          replay_export: "fixture_backed"
        },
        preflight: %{
          evidence_readback: "fixture_backed",
          trace_export_metrics_truth: "not_used"
        },
        metadata: %{source: "Synapse.Evidence"}
      })

    %{
      status: :fixture_backed,
      runtime_status: snapshot,
      health_rows: [
        %{id: "appkit-surfaces", label: "AppKit surfaces", state: :ok},
        %{id: "projection-lag", label: "Projection lag", state: :fixture_backed},
        %{id: "binding-lookup", label: "Binding lookup", state: :not_live},
        %{id: "authority-latency", label: "Authority latency", state: :fixture_backed},
        %{id: "lower-errors", label: "Lower invocation errors", state: :none_projected},
        %{id: "trace-export", label: "Trace export", state: :separate_from_ops_health}
      ]
    }
  end

  @spec runtime_facts(keyword()) :: struct()
  def runtime_facts(_opts \\ []) do
    {:ok, event} =
      RuntimeEventSummary.new(%{
        event_kind: "projection_updated",
        count: 2,
        latest_event_ref: "event://synapse/projection-updated"
      })

    {:ok, facts} =
      RuntimeFactsProjection.new(%{
        token_totals: %{state: "redacted"},
        token_dedupe: %{state: "ok"},
        rate_limit: %{state: "not_projected"},
        retry_queue: [],
        aitrace: %{export_state: "separate"},
        prompt: %{state: "refs_only"},
        semantic: %{state: "fixture_backed"},
        authority: %{state: "authorized"},
        events: [event],
        metadata: %{source: "fixture"}
      })

    facts
  end

  defp evidence_view!(attrs) do
    {:ok, projection} =
      EvidenceProjection.new(%{
        evidence_ref: attrs.evidence_ref,
        evidence_kind: attrs.evidence_kind,
        status: attrs.status,
        content_ref: attrs.content_ref,
        metadata: %{
          run_ref: attrs.run_ref,
          receipt_ref: attrs.receipt_ref,
          missing_reason: Map.get(attrs, :missing_reason)
        }
      })

    Map.put(attrs, :projection, projection)
  end

  defp receipt_view!(attrs) do
    {:ok, receipt} =
      LowerReceiptSummary.new(%{
        receipt_ref: attrs.receipt_ref,
        receipt_state: "recorded",
        lower_receipt_ref: "lower-receipt://synapse/#{attrs.id}",
        run_ref: attrs.run_ref,
        attempt_ref: "attempt://synapse/#{attrs.id}",
        execution_ref: %{
          id: "execution://synapse/#{attrs.id}",
          dispatch_state: :accepted
        },
        metadata: %{
          "evidence_ref" => attrs.evidence_ref,
          "trace_ref" => Map.get(attrs, :trace_ref),
          "trace_summary_hash" => Map.get(attrs, :trace_summary_hash)
        }
      })

    %{
      id: attrs.id,
      evidence_ref: attrs.evidence_ref,
      receipt: receipt
    }
  end

  defp evidence_items(opts) do
    @evidence_items ++ governed_effect_items(Keyword.get(opts, :governed_effects, []))
  end

  defp governed_effect_items(effects) when is_list(effects) do
    effects
    |> Enum.map(&governed_effect_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp governed_effect_items(_effects), do: []

  defp governed_effect_item(effect) when is_map(effect) do
    effect_ref = map_value(effect, :effect_ref)
    receipt_ref = map_value(effect, :receipt_ref)
    evidence_refs = map_value(effect, :evidence_refs) || []

    evidence_ref =
      first_binary(evidence_refs) || "evidence://synapse/effects/#{effect_id(effect_ref)}"

    %{
      id: "governed-effect-#{effect_id(effect_ref)}",
      evidence_ref: evidence_ref,
      evidence_kind: "governed_effect",
      status: if(is_binary(receipt_ref), do: "available", else: "missing"),
      content_ref: map_value(effect, :content_ref),
      effect_ref: effect_ref,
      authority_ref: map_value(effect, :authority_ref),
      receipt_ref: receipt_ref,
      run_ref: map_value(effect, :run_ref) || "run://synapse/governed-effect",
      trace_ref: map_value(effect, :trace_ref),
      trace_summary_hash: map_value(effect, :trace_summary_hash),
      lifecycle_entries: lifecycle_entries(effect),
      diagnostic_result: diagnostic_result(effect)
    }
  end

  defp governed_effect_item(_effect), do: nil

  defp first_binary(values) when is_list(values), do: Enum.find(values, &is_binary/1)
  defp first_binary(_values), do: nil

  defp lifecycle_entries(effect) do
    effect
    |> map_value(:lifecycle_entries)
    |> case do
      entries when is_list(entries) -> entries
      _other -> []
    end
  end

  defp diagnostic_result(effect) do
    metadata =
      effect
      |> map_value(:metadata)
      |> case do
        %{} = value -> value
        _other -> %{}
      end

    Map.get(metadata, "diagnostic_result", Map.get(metadata, :diagnostic_result))
  end

  defp effect_id(value) when is_binary(value) do
    value
    |> String.split("/", trim: true)
    |> List.last()
  end

  defp effect_id(_value), do: "unknown"

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
