defmodule Synapse.Orchestrator.AgentConfigTest do
  use ExUnit.Case, async: true

  alias Synapse.Orchestrator.AgentConfig

  describe "new/1" do
    test "returns struct for specialist with required fields" do
      config = %{
        id: :demo_agent,
        type: :specialist,
        actions: [Sample.Action],
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      }

      assert {:ok, %AgentConfig{} = result} = AgentConfig.new(config)
      assert result.id == :demo_agent
      assert result.actions == [Sample.Action]
    end

    test "errors when specialist is missing actions" do
      config = %{
        id: :invalid_agent,
        type: :specialist,
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      }

      assert {:error, %NimbleOptions.ValidationError{} = error} = AgentConfig.new(config)
      assert error.message =~ "specialist agents must define at least one action module"
    end
  end
end
