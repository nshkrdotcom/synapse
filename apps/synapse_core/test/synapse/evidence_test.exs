defmodule Synapse.EvidenceTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.{EvidenceProjection, LowerReceiptSummary, RuntimeFactsProjection}
  alias AppKit.Core.RuntimeSurface.RuntimeStatusSnapshot
  alias AppKit.ReplaySurface.ReplayBundleProjection
  alias Synapse.Evidence

  test "lists product-safe evidence projections and explicit missing evidence" do
    evidence = Evidence.list_evidence()

    assert Enum.all?(evidence, &match?(%EvidenceProjection{}, &1.projection))
    assert Enum.any?(evidence, &(&1.status == "missing"))
    refute Enum.any?(evidence, &Map.has_key?(&1, :body))
  end

  test "returns lower receipt summaries" do
    assert {:ok, receipt} = Evidence.get_receipt("receipt://synapse/run-start")

    assert %LowerReceiptSummary{} = receipt.receipt
    assert receipt.receipt.receipt_state == "recorded"
  end

  test "includes governed-effect evidence and receipts when supplied by staged-live run" do
    effect = %{
      effect_ref: "effect://synapse/diagnostic-live/echo",
      effect_type: "diagnostic.echo",
      command_ref: "command://synapse/diagnostic-live",
      status: "authorized",
      run_ref: "run://live-stack/diagnostic-live",
      receipt_ref: "receipt://synapse/effects/diagnostic",
      trace_ref: "trace://synapse/diagnostic-live",
      trace_summary_hash: "sha256:synapse-diagnostic",
      evidence_refs: ["evidence://synapse/effects/diagnostic"]
    }

    evidence = Evidence.list_evidence(governed_effects: [effect])

    assert Enum.any?(evidence, fn item ->
             item.evidence_ref == "evidence://synapse/effects/diagnostic" and
               item.evidence_kind == "governed_effect" and
               item.status == "available"
           end)

    assert {:ok, receipt} =
             Evidence.get_receipt(
               "receipt://synapse/effects/diagnostic",
               governed_effects: [effect]
             )

    assert %LowerReceiptSummary{} = receipt.receipt
    assert receipt.receipt.run_ref == "run://live-stack/diagnostic-live"
    assert receipt.receipt.metadata["trace_ref"] == "trace://synapse/diagnostic-live"
  end

  test "builds replay bundle and divergence projections" do
    replay = Evidence.replay_bundle()

    assert %ReplayBundleProjection{} = replay.bundle
    assert replay.bundle.decision_class == :diverged
    assert [%{severity: :warn}] = replay.divergences
  end

  test "keeps operational health separate from trace export truth" do
    ops = Evidence.operations()

    assert %RuntimeStatusSnapshot{} = ops.runtime_status
    assert ops.runtime_status.preflight["trace_export_metrics_truth"] == "not_used"
    assert Enum.any?(ops.health_rows, &(&1.state == :separate_from_ops_health))
  end

  test "builds runtime facts projection" do
    assert %RuntimeFactsProjection{} = Evidence.runtime_facts()
  end
end
