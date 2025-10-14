# synapse/test/synapse/fault_tolerance_test.exs

defmodule SynapseCore.FaultToleranceTest do
  use ExUnit.Case, async: true

  setup do
    # Start your application or necessary supervisors
    # You might need to adjust this depending on your application's setup
    start_supervised(SynapseCore.Application)

    :ok
  end

  @tag :capture_log
  test "restarts Python agent on crash during request" do
    agent_id = "python_agent_1"

    # Send a request that will cause the agent to crash
    # You'll need to implement this in your test agent or agent_wrapper
    # agent_pid = get_agent_pid(agent_id)

    # Ensure agent process exists before attempting to send a message
    assert Process.alive?(SynapseCore.Agent.Server.pid(agent_id))

    send_message(agent_id, %{prompt: "crash"})

    # Wait for the agent to crash and be restarted
    ref = Process.monitor(SynapseCore.Agent.Server.pid(agent_id))

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} ->
        # Agent process has been restarted
        :ok
    after
      5000 ->
        flunk("Agent did not restart within expected time")
    end

    # Wait for a short period to allow the new process to fully start
    Process.sleep(1000)

    # Assert the new process is alive
    assert Process.alive?(SynapseCore.Agent.Server.pid(agent_id))

    # Send another request to ensure the agent is functioning again
    {:ok, result} = send_message(agent_id, %{prompt: "hello"})
    assert is_map(result)
  end
end
