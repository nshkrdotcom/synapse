defmodule Synapse.Workflow.EngineTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step

  alias Synapse.Workflow.EngineTest.Support.{
    AddAction,
    RecordOrderAction,
    FlakyAction,
    AlwaysFailAction
  }

  setup context do
    handler_id = {__MODULE__, context.test}

    :telemetry.attach_many(
      handler_id,
      telemetry_events(),
      fn event, measurements, metadata, _ ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    :persistent_term.put(:engine_test_flaky_attempts, 0)
    :persistent_term.put(:engine_test_execution_order, [])

    on_exit(fn ->
      :telemetry.detach(handler_id)
      :persistent_term.erase(:engine_test_flaky_attempts)
      :persistent_term.erase(:engine_test_execution_order)
    end)

    :ok
  end

  describe "execute/2" do
    test "runs sequential steps and returns outputs + audit metadata" do
      spec =
        Spec.new(
          name: :demo,
          description: "sequential test",
          steps: [
            Step.new(
              id: :add,
              action: AddAction,
              label: "Add base",
              params: fn env -> %{value: Map.fetch!(env.input, :start)} end
            ),
            Step.new(
              id: :double,
              action: AddAction,
              requires: [:add],
              description: "double previous result",
              params: fn env -> %{value: env.results.add * 2} end
            )
          ],
          outputs: [
            Spec.output(:executor_output, from: :add),
            Spec.output(:total, from: :double)
          ]
        )

      {:ok, exec} =
        Engine.execute(spec, input: %{start: 3}, context: %{base: 1}, persistence: nil)

      assert exec.outputs.executor_output == 4
      assert exec.outputs.total == 9
      assert Enum.sort(Map.keys(exec.results)) == [:add, :double]

      assert exec.audit_trail.workflow == :demo
      assert length(exec.audit_trail.steps) == 2
      assert Enum.all?(exec.audit_trail.steps, &(&1.status == :ok))

      assert_received {:telemetry_event, [:synapse, :workflow, :step, :start], _, %{step: :add}}
      assert_received {:telemetry_event, [:synapse, :workflow, :step, :stop], _, %{step: :double}}
    end

    test "obeys dependencies even when steps are declared out of order" do
      spec =
        Spec.new(
          name: :deps,
          steps: [
            Step.new(
              id: :finalize,
              action: RecordOrderAction,
              requires: [:prepare],
              params: fn env -> %{payload: env.results.prepare} end
            ),
            Step.new(
              id: :prepare,
              action: RecordOrderAction,
              params: %{payload: :ready}
            )
          ],
          outputs: [Spec.output(:result, from: :finalize)]
        )

      {:ok, exec} = Engine.execute(spec, persistence: nil)

      assert exec.outputs.result == :ready

      assert Enum.reverse(:persistent_term.get(:engine_test_execution_order, [])) == [
               :prepare,
               :finalize
             ]
    end

    test "retries flaky steps and emits telemetry" do
      Process.put(:flaky_attempts, 0)

      spec =
        Spec.new(
          name: :flaky,
          steps: [
            Step.new(
              id: :retry_me,
              action: FlakyAction,
              retry: %{max_attempts: 3},
              params: %{value: :ok}
            )
          ],
          outputs: [Spec.output(:final, from: :retry_me)]
        )

      {:ok, exec} = Engine.execute(spec, persistence: nil)

      assert exec.outputs.final == :ok
      assert :persistent_term.get(:engine_test_flaky_attempts, 0) == 2

      assert_received {:telemetry_event, [:synapse, :workflow, :step, :stop], _,
                       %{step: :retry_me}}
    end

    test "returns error and audit trail when retries are exhausted" do
      spec =
        Spec.new(
          name: :failure,
          steps: [
            Step.new(
              id: :explode,
              action: AlwaysFailAction,
              retry: %{max_attempts: 2},
              params: %{value: :nope}
            )
          ]
        )

      assert {:error, failure} = Engine.execute(spec, persistence: nil)
      assert failure.failed_step == :explode
      assert match?(%Jido.Error{}, failure.error)
      assert failure.attempts == 2
      assert failure.audit_trail.workflow == :failure

      [step_audit] = failure.audit_trail.steps
      assert step_audit.status == :error
      assert step_audit.attempts == 2

      assert_received {:telemetry_event, [:synapse, :workflow, :step, :exception], _,
                       %{step: :explode}}
    end

    test "continues execution when step on_error is :continue" do
      spec =
        Spec.new(
          name: :soft_fail,
          steps: [
            Step.new(
              id: :unstable,
              action: AlwaysFailAction,
              params: %{value: :ignored},
              on_error: :continue
            ),
            Step.new(
              id: :downstream,
              action: AddAction,
              requires: [:unstable],
              params: %{value: 5}
            )
          ],
          outputs: [Spec.output(:result, from: :downstream)]
        )

      {:ok, exec} = Engine.execute(spec, persistence: nil)

      assert exec.outputs.result == 5

      assert %{status: :error, error: %Jido.Error{}} = exec.results.unstable
      assert exec.results.downstream == 5

      assert Enum.find(exec.audit_trail.steps, &(&1.step == :unstable)).status == :error
      assert Enum.find(exec.audit_trail.steps, &(&1.step == :downstream)).status == :ok
    end
  end

  defp telemetry_events do
    [
      [:synapse, :workflow, :step, :start],
      [:synapse, :workflow, :step, :stop],
      [:synapse, :workflow, :step, :exception]
    ]
  end
end

defmodule Synapse.Workflow.EngineTest.Support.AddAction do
  use Jido.Action,
    name: "engine_test_add",
    schema: [value: [type: :integer, required: true]]

  @impl true
  def run(params, context) do
    {:ok, params.value + Map.get(context, :base, 0)}
  end
end

defmodule Synapse.Workflow.EngineTest.Support.RecordOrderAction do
  use Jido.Action,
    name: "engine_test_record",
    schema: [payload: [type: :any, required: true]]

  @impl true
  def run(params, context) do
    order = :persistent_term.get(:engine_test_execution_order, [])
    :persistent_term.put(:engine_test_execution_order, [context.workflow_step | order])
    {:ok, params.payload}
  end
end

defmodule Synapse.Workflow.EngineTest.Support.FlakyAction do
  use Jido.Action,
    name: "engine_test_flaky",
    schema: [value: [type: :any, required: true]]

  @impl true
  def run(params, _context) do
    attempts = :persistent_term.get(:engine_test_flaky_attempts, 0)

    case attempts do
      0 ->
        :persistent_term.put(:engine_test_flaky_attempts, attempts + 1)
        {:error, Jido.Error.execution_error("try again")}

      _ ->
        :persistent_term.put(:engine_test_flaky_attempts, attempts + 1)
        {:ok, params.value}
    end
  end
end

defmodule Synapse.Workflow.EngineTest.Support.AlwaysFailAction do
  use Jido.Action,
    name: "engine_test_fail",
    schema: [value: [type: :any, required: true]]

  @impl true
  def run(_params, _context) do
    {:error, Jido.Error.execution_error("boom")}
  end
end
