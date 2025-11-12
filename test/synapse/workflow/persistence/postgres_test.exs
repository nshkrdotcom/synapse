defmodule Synapse.Workflow.Persistence.PostgresTest do
  use Synapse.SupertesterCase, async: false

  @moduletag :capture_log

  alias Synapse.Workflow.{Engine, Execution, Spec}
  alias Synapse.Workflow.Spec.Step
  alias Synapse.Workflow.Persistence.Postgres
  alias Synapse.Workflow.Persistence.Snapshot

  @request_id "test-request"

  setup do
    Synapse.Repo.delete_all(Execution)
    :ok
  end

  test "persists snapshots for successful workflows" do
    spec = demo_spec(:persist_success)

    {:ok, _result} =
      Engine.execute(spec,
        input: %{value: 2},
        context: %{request_id: @request_id},
        persistence: {Postgres, []}
      )

    assert {:ok, %Snapshot{} = snapshot} = Postgres.get_snapshot(@request_id, [])
    assert snapshot.status == "completed"
    assert snapshot.spec_name == "persist_success"
    assert get_in(snapshot.results, ["calculate", "result"]) == 4
    assert Map.get(snapshot.audit_trail, "status") in ["completed", "ok"]
  end

  test "persists failure snapshots with error metadata" do
    spec = demo_spec(:persist_failure, force_error?: true)

    assert {:error, _failure} =
             Engine.execute(spec,
               input: %{value: 1},
               context: %{request_id: "fail-request"},
               persistence: {Postgres, []}
             )

    assert {:ok, snapshot} = Postgres.get_snapshot("fail-request", [])
    assert snapshot.status == "failed"
    assert Map.get(snapshot.error, "message") =~ "boom"
    assert snapshot.last_step_id == "calculate"
  end

  defp demo_spec(name, opts \\ []) do
    Step.new(
      id: :calculate,
      action: __MODULE__.DemoAction,
      params: fn env ->
        %{
          force_error?: !!opts[:force_error?],
          value: Map.get(env.input, :value, Map.get(env.input, "value", 1))
        }
      end
    )
    |> then(fn step ->
      Spec.new(
        name: name,
        metadata: %{version: 1},
        steps: [step],
        outputs: [Spec.output(:result, from: :calculate)]
      )
    end)
  end

  defmodule DemoAction do
    use Jido.Action,
      name: "persistence_demo",
      schema: [force_error?: [type: :boolean, default: false]]

    @impl true
    def run(params, _context) do
      if params.force_error? do
        {:error, Jido.Error.execution_error("boom")}
      else
        {:ok, %{result: 2 * Map.get(params, :value, 2)}}
      end
    end
  end
end
