defmodule Synapse.Agents.SimpleExecutorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Synapse.TestSupport.AgentHelpers

  alias Synapse.Agents.SimpleExecutor
  alias Synapse.Actions.Echo

  describe "SimpleExecutor agent" do
    test "can start agent server" do
      # Capture expected termination logs from GenServer.stop
      capture_log(fn ->
        {:ok, pid} = SimpleExecutor.start_link()
        assert Process.alive?(pid)
        GenServer.stop(pid)
      end)
    end

    test "can execute action using agent struct" do
      agent = SimpleExecutor.new()

      # Use helper to reduce boilerplate
      agent = exec_agent_cmd(agent, {Echo, %{message: "test"}})

      # Use helpers for cleaner assertions
      assert_agent_result(agent, %{message: "test"})
      assert_agent_state(agent, execution_count: 1)
    end

    test "can execute action with params using tuple format" do
      agent = SimpleExecutor.new()

      agent = exec_agent_cmd(agent, {Echo, %{message: "Hello!"}})

      assert_agent_result(agent, %{message: "Hello!"})
      assert_agent_state(agent, execution_count: 1)
    end

    test "maintains state across multiple commands" do
      agent = SimpleExecutor.new()

      # Use exec_agent_cmds for multiple commands
      agent =
        exec_agent_cmds(agent, [
          {Echo, %{message: "First"}},
          {Echo, %{message: "Second"}},
          {Echo, %{message: "Third"}}
        ])

      # Final state assertion
      assert_agent_state(agent, execution_count: 3)

      # Verify final result
      result = get_agent_result(agent)
      assert result.message == "Third"
    end

    test "returns error for unknown action" do
      agent = SimpleExecutor.new()

      defmodule FakeAction do
        # Not a real action, not registered with agent
      end

      {:error, error} = SimpleExecutor.cmd(agent, FakeAction)

      assert error.message =~ "not registered"
    end
  end
end
