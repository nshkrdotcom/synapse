defmodule Synapse.Workflow.EmissionTest do
  use ExUnit.Case, async: false

  alias Synapse.Actions.Echo
  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step

  setup do
    {:ok, _} = start_supervised(Synapse.LineageIRTestAdapter)
    {:ok, _} = start_supervised(Synapse.RunIndexTestAdapter)
    {:ok, _} = start_supervised(Synapse.WorkEmitterTestAdapter)

    Synapse.LineageIRTestAdapter.reset()
    Synapse.RunIndexTestAdapter.reset()
    Synapse.WorkEmitterTestAdapter.reset()

    :ok
  end

  test "emits lineage, run index, and work events during workflow execution" do
    spec =
      Spec.new(
        name: :emit_demo,
        steps: [
          Step.new(
            id: :emit,
            action: Echo,
            params: %{message: "hello"}
          )
        ],
        outputs: [Spec.output(:result, from: :emit)]
      )

    assert {:ok, _} =
             Engine.execute(spec,
               input: %{},
               context: %{request_id: "req-emit", tenant_id: "acme"},
               persistence: nil,
               lineage_ir: true,
               lineage_opts: [adapter: Synapse.LineageIRTestAdapter],
               run_index_adapter: Synapse.RunIndexTestAdapter,
               work_adapter: Synapse.WorkEmitterTestAdapter
             )

    lineage = Synapse.LineageIRTestAdapter.data()
    event_types = Enum.map(lineage.events, & &1.type)

    assert "trace_start" in event_types
    assert "span_start" in event_types
    assert "span_end" in event_types
    assert "artifact" in event_types
    assert [_ | _] = lineage.spans
    assert [_ | _] = lineage.artifacts

    run_index = Synapse.RunIndexTestAdapter.data()

    assert Enum.any?(run_index.runs, &(&1.status == "running"))
    assert Enum.any?(run_index.runs, &(&1.status == "succeeded"))
    assert Enum.any?(run_index.steps, &(&1.status == "running" and &1.step_key == "emit"))
    assert Enum.any?(run_index.steps, &(&1.status == "succeeded" and &1.step_key == "emit"))

    work = Synapse.WorkEmitterTestAdapter.data()

    assert Enum.any?(work.events, fn {event, _job} -> event == :started end)
    assert Enum.any?(work.events, fn {event, _job} -> event == :succeeded end)
  end
end
