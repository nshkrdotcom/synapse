defmodule Synapse.TelemetryTest do
  use ExUnit.Case, async: true

  @event [:synapse, :workflow, :orchestrator, :summary]

  test "default orchestrator handler can be installed multiple times" do
    assert :ok = Synapse.Telemetry.attach_orchestrator_summary_handler()

    handlers = :telemetry.list_handlers(@event)

    assert Enum.any?(handlers, &(&1.id == "synapse-orchestrator-summary-logger"))
  end

  test "custom handler can be attached without logging" do
    handler_id = "synapse-orchestrator-summary-test-#{System.unique_integer([:positive])}"

    assert :ok =
             Synapse.Telemetry.attach_orchestrator_summary_handler(
               handler_id: handler_id,
               log?: false
             )

    on_exit(fn ->
      Synapse.Telemetry.detach_orchestrator_summary_handler(handler_id: handler_id)
    end)

    :telemetry.execute(
      @event,
      %{duration_ms: 42, finding_count: 1, recommendation_count: 1},
      %{
        config_id: :test,
        review_id: "test",
        status: :complete,
        severity: :high,
        decision_path: :deep_review,
        specialists: ["security_specialist"],
        escalations: [],
        negotiations: [%{agents: ["security_specialist"], resolution: :prefer_highest_severity}]
      }
    )
  end
end
