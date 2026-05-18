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
