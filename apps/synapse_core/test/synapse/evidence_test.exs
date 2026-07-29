defmodule Synapse.EvidenceTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.{EvidenceProjection, RuntimeFactsProjection}
  alias AppKit.Core.ProductSurface.OperationProjection
  alias AppKit.Core.RuntimeSurface.RuntimeStatusSnapshot
  alias Synapse.Evidence

  test "lists refs-only evidence projected from durable artifacts and operations" do
    evidence = Evidence.list_evidence()

    assert Enum.all?(evidence, &match?(%EvidenceProjection{}, &1.projection))
    assert Enum.any?(evidence, &(&1.evidence_ref == "evidence://synapse/test-run/output"))
    assert Enum.any?(evidence, &(&1.evidence_ref == "evidence://synapse/test-run/model/1"))
    refute Enum.any?(evidence, &Map.has_key?(&1, :body))
  end

  test "returns the exact owner operation behind a receipt" do
    assert {:ok, receipt} = Evidence.get_receipt("receipt://synapse/test-run/model/1")

    assert receipt.state == :completed
    assert receipt.run_ref == "run://durable/test-run"
    assert %OperationProjection{} = receipt.operation
  end

  test "does not synthesize replay state without an owner projection" do
    replay = Evidence.replay_bundle()

    assert replay.status == :unavailable
    assert replay.bundle == nil
    assert replay.divergences == []
  end

  test "keeps operational health separate from trace export truth" do
    ops = Evidence.operations()

    assert ops.status == :available
    assert %RuntimeStatusSnapshot{} = ops.runtime_status
    assert ops.runtime_status.preflight["trace_export_metrics_truth"] == "not_used"
    assert Enum.any?(ops.health_rows, &(&1.state == "separate_from_ops_health"))
    assert [%OperationProjection{state: :completed}] = ops.operation_rows
  end

  test "builds runtime facts projection" do
    assert {:ok, %RuntimeFactsProjection{} = facts} = Evidence.runtime_facts()
    assert facts.metadata["source"] == "AppKit.ProductSurface"
    assert facts.semantic["operation_count"] == 1
  end

  test "fails closed when the product projection role is absent" do
    stack = Synapse.Test.AppKitBackendStack.backend_stack()
    missing = %{stack | backends: Map.delete(stack.backends, :product_surface_backend)}

    assert %{status: :unavailable, evidence: [], artifacts: []} =
             Evidence.snapshot(app_kit_backend_stack: missing)
  end
end
