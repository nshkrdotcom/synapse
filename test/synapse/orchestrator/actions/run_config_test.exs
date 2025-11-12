defmodule Synapse.Orchestrator.Actions.RunConfigTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Jido.{Exec, Signal}
  alias Synapse.Orchestrator.Actions.RunConfig
  alias Synapse.SignalRouter

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Synapse.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Synapse.Repo, {:shared, self()})
  end

  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      schema: [value: [type: :integer, required: true]]

    @impl true
    def run(params, _context) do
      {:ok, %{value: params.value + 1}}
    end
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      schema: []

    @impl true
    def run(_params, _context) do
      {:error, Jido.Error.execution_error("boom")}
    end
  end

  defp base_config(actions) do
    %Synapse.Orchestrator.AgentConfig{
      id: :demo_agent,
      type: :specialist,
      signals: %{subscribes: [], emits: []},
      actions: actions,
      result_builder: fn results, payload ->
        %{payload: payload, results: results}
      end
    }
  end

  test "executes actions via workflow engine and returns audit trail" do
    {:ok, response} =
      Exec.run(RunConfig, %{_config: base_config([TestAction]), value: 1}, %{})

    assert [{:ok, TestAction, %{value: 2}}] = response.results
    assert response.audit_trail.workflow == :orchestrator_run_config
    assert response.result.payload.value == 1
  end

  alias Jido.Error

  test "wraps failing actions without aborting workflow" do
    {:ok, response} =
      Exec.run(RunConfig, %{_config: base_config([FailingAction]), value: 5}, %{})

    assert [
             {:error, FailingAction, %Error{message: message}}
           ] = response.results

    assert message == "boom"
    assert response.audit_trail.status in [:completed, :ok]
  end

  test "emits telemetry for orchestrator summaries" do
    handler_id = "orchestrator-summary-test-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [[:synapse, :workflow, :orchestrator, :summary]],
        fn event, measurements, metadata, _config ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    router_name = :"router_#{System.unique_integer([:positive])}"
    start_supervised!({SignalRouter, name: router_name})

    config = %Synapse.Orchestrator.AgentConfig{
      id: :telemetry_coordinator,
      type: :orchestrator,
      actions: [],
      signals: %{subscribes: [:review_request], emits: [:review_summary]},
      orchestration: %{
        classify_fn: fn _ -> %{path: :fast_path, rationale: "test"} end,
        aggregation_fn: fn _results, review_state ->
          %{
            review_id: review_state.review_id,
            status: :complete,
            severity: :none,
            findings: [],
            recommendations: [],
            escalations: [],
            metadata: review_state.metadata
          }
        end
      }
    }

    signal =
      Signal.new!(%{
        type: Synapse.Signal.type(:review_request),
        data: %{
          review_id: "telemetry-#{System.unique_integer([:positive])}",
          diff: "",
          labels: [],
          files_changed: 1
        }
      })

    {:ok, _} =
      Exec.run(
        RunConfig,
        %{_config: config, _router: router_name, _signal: signal},
        %{}
      )

    assert_receive {:telemetry_event, [:synapse, :workflow, :orchestrator, :summary],
                    %{duration_ms: _duration, finding_count: 0}, metadata},
                   1_000

    assert metadata.config_id == :telemetry_coordinator
    assert metadata.status == :complete
    assert metadata.severity == :none
  end
end
