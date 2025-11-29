defmodule Synapse.Orchestrator.Actions.RunConfigTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Jido.{Exec, Signal}
  alias Synapse.Orchestrator.AgentConfig
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

  describe "config-driven signal dispatch" do
    setup do
      router_name = :"router_#{System.unique_integer([:positive])}"
      start_supervised!({SignalRouter, name: router_name})

      {:ok, router: router_name}
    end

    test "dispatches based on roles.request topic", %{router: router} do
      config = %AgentConfig{
        id: :test_coordinator,
        type: :orchestrator,
        signals: %{
          subscribes: [:task_request, :task_result],
          emits: [:task_summary],
          roles: %{request: :task_request, result: :task_result, summary: :task_summary}
        },
        actions: [],
        orchestration: %{
          classify_fn: fn _ -> %{path: :fast_path} end,
          spawn_specialists: [],
          aggregation_fn: fn _, state -> %{task_id: state.task_id, status: :complete} end
        }
      }

      {:ok, signal} =
        Signal.new(%{
          type: "synapse.task.request",
          source: "/test",
          data: %{task_id: "test-123", payload: %{}}
        })

      params = %{_config: config, _signal: signal, _state: nil, _router: router}

      assert {:ok, %{state: state}} = RunConfig.run(params, %{})
      assert state.stats.total == 1
      assert state.stats.routed == 1
      assert state.tasks == %{}
    end

    test "dispatches based on roles.result topic", %{router: router} do
      config = %AgentConfig{
        id: :test_coordinator,
        type: :orchestrator,
        signals: %{
          subscribes: [:task_request, :task_result],
          emits: [:task_summary],
          roles: %{request: :task_request, result: :task_result, summary: :task_summary}
        },
        actions: [],
        orchestration: %{
          classify_fn: fn _ -> %{path: :deep_review} end,
          spawn_specialists: [:worker_a],
          aggregation_fn: fn results, state ->
            %{task_id: state.task_id, status: :complete, results: results}
          end
        }
      }

      {:ok, request_signal} =
        Signal.new(%{
          type: "synapse.task.request",
          source: "/test",
          data: %{task_id: "test-456", payload: %{}}
        })

      {:ok, %{state: state}} =
        RunConfig.run(
          %{
            _config: config,
            _signal: request_signal,
            _state: nil,
            _router: router
          },
          %{}
        )

      {:ok, result_signal} =
        Signal.new(%{
          type: "synapse.task.result",
          source: "/test",
          data: %{task_id: "test-456", agent: "worker_a", output: %{}}
        })

      assert {:ok, %{state: updated_state}} =
               RunConfig.run(
                 %{
                   _config: config,
                   _signal: result_signal,
                   _state: state,
                   _router: router
                 },
                 %{}
               )

      assert updated_state.stats.completed >= 1
    end

    test "uses legacy review topics when roles not specified", %{router: router} do
      config = %AgentConfig{
        id: :legacy_coordinator,
        type: :orchestrator,
        signals: %{
          subscribes: [:review_request, :review_result],
          emits: [:review_summary],
          roles: nil
        },
        actions: [],
        orchestration: %{
          classify_fn: fn _ -> %{path: :fast_path} end,
          spawn_specialists: [],
          aggregation_fn: fn _, state ->
            %{review_id: state.task_id, status: :complete}
          end
        }
      }

      {:ok, signal} =
        Signal.new(%{
          type: Synapse.Signal.type(:review_request),
          source: "/test",
          data: %{review_id: "PR-123", diff: ""}
        })

      params = %{_config: config, _signal: signal, _state: nil, _router: router}

      assert {:ok, _result} = RunConfig.run(params, %{})
    end
  end

  describe "generic state keys" do
    setup do
      router_name = :"router_#{System.unique_integer([:positive])}"
      start_supervised!({SignalRouter, name: router_name})

      {:ok, router: router_name}
    end

    test "uses tasks instead of reviews in state", %{router: router} do
      config = orchestrator_config()

      {:ok, signal} =
        Signal.new(%{
          type: "synapse.task.request",
          source: "/test",
          data: %{task_id: "state-test-123", payload: %{}}
        })

      {:ok, result} =
        RunConfig.run(
          %{
            _config: config,
            _signal: signal,
            _state: nil,
            _router: router
          },
          %{}
        )

      assert Map.has_key?(result.state, :tasks)
      refute Map.has_key?(result.state, :reviews)
    end

    test "stats use generic keys", %{router: router} do
      config = orchestrator_config()

      {:ok, signal} =
        Signal.new(%{
          type: "synapse.task.request",
          source: "/test",
          data: %{task_id: "stats-test", payload: %{}}
        })

      {:ok, result} =
        RunConfig.run(
          %{
            _config: config,
            _signal: signal,
            _state: nil,
            _router: router
          },
          %{}
        )

      stats = result.state.stats
      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :routed) or Map.has_key?(stats, :dispatched)
    end
  end

  defp orchestrator_config do
    %AgentConfig{
      id: :test_coord,
      type: :orchestrator,
      signals: %{
        subscribes: [:task_request, :task_result],
        emits: [:task_summary],
        roles: %{request: :task_request, result: :task_result, summary: :task_summary}
      },
      actions: [],
      orchestration: %{
        classify_fn: fn _ -> %{path: :routed} end,
        spawn_specialists: [],
        aggregation_fn: fn _, state -> %{task_id: state.task_id, status: :complete} end
      }
    }
  end
end
