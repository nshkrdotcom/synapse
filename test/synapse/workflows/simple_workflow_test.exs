defmodule Synapse.Workflows.SimpleWorkflowTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Echo

  describe "Simple action execution via Jido.Exec" do
    test "can run single action directly" do
      {:ok, result} = Jido.Exec.run(Echo, %{message: "Hello from Exec!"})

      assert result.message == "Hello from Exec!"
    end

    test "can pass context to actions" do
      defmodule ContextAwareAction do
        use Jido.Action,
          name: "context_aware",
          description: "Uses context in execution",
          schema: [value: [type: :string, required: true]]

        def run(params, context) do
          {:ok,
           %{
             value: params.value,
             has_context: map_size(context) > 0,
             context_data: Map.get(context, :shared_data)
           }}
        end
      end

      {:ok, result} =
        Jido.Exec.run(
          ContextAwareAction,
          %{value: "test"},
          %{shared_data: "available"}
        )

      assert result.value == "test"
      assert result.has_context == true
      assert result.context_data == "available"
    end

    test "can use agent for sequential workflow" do
      alias Synapse.Agents.SimpleExecutor

      agent = SimpleExecutor.new()

      # Execute actions in sequence using agent
      {:ok, agent, _} = SimpleExecutor.cmd(agent, {Echo, %{message: "step1"}})
      assert agent.result.message == "step1"
      assert agent.state.execution_count == 1

      {:ok, agent, _} = SimpleExecutor.cmd(agent, {Echo, %{message: "step2"}})
      assert agent.result.message == "step2"
      assert agent.state.execution_count == 2

      {:ok, agent, _} = SimpleExecutor.cmd(agent, {Echo, %{message: "step3"}})
      assert agent.result.message == "step3"
      assert agent.state.execution_count == 3
    end
  end
end
