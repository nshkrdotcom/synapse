defmodule Synapse.Orchestrator.Runtime.RunningAgentTest do
  use ExUnit.Case, async: true

  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.Orchestrator.Runtime.RunningAgent

  test "new/1 validates required fields" do
    {:ok, config} =
      AgentConfig.new(%{
        id: :demo,
        type: :specialist,
        actions: [Demo.Action],
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      })

    attrs = [
      agent_id: :demo,
      pid: self(),
      config: config,
      monitor_ref: make_ref(),
      spawned_at: DateTime.utc_now(),
      spawn_count: 1
    ]

    assert {:ok, %RunningAgent{} = running} = RunningAgent.new(attrs)
    assert running.agent_id == :demo
  end

  test "new/1 rejects invalid pid" do
    {:ok, config} =
      AgentConfig.new(%{
        id: :demo,
        type: :specialist,
        actions: [Demo.Action],
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      })

    assert {:error, %NimbleOptions.ValidationError{} = error} =
             RunningAgent.new(
               agent_id: :demo,
               pid: :not_a_pid,
               config: config,
               monitor_ref: make_ref(),
               spawned_at: DateTime.utc_now(),
               spawn_count: 1
             )

    assert error.message =~ "must be a PID"
  end
end
