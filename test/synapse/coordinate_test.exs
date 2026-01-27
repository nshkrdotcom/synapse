defmodule Synapse.CoordinateTest do
  use ExUnit.Case, async: true

  alias Synapse.{DelegationResult, CoordinatorSpec}

  describe "Synapse.coordinate/3" do
    test "returns {:ok, result} when consensus reached" do
      spec = %{
        coordinator: :test_coordinator,
        agents: [:agent_a, :agent_b],
        max_iterations: 5,
        consensus_threshold: 0.8,
        escalation_policy: :on_no_consensus
      }

      inputs = %{data: "test input"}

      context = %{
        timeout_remaining_ms: 300_000,
        test_mode: true,
        mock_responses: %{
          agent_a: fn _input -> {:ok, %{position: :approve, score: 1.0}} end,
          agent_b: fn _input -> {:ok, %{position: :approve, score: 1.0}} end
        }
      }

      assert {:ok, %DelegationResult{status: :success}} =
               Synapse.coordinate(spec, inputs, context)
    end

    test "returns {:escalate, result} when max_iterations reached without consensus" do
      spec = %{
        coordinator: :test_coordinator,
        agents: [:agent_a, :agent_b],
        max_iterations: 2,
        consensus_threshold: 0.9,
        escalation_policy: :on_no_consensus
      }

      inputs = %{data: "test input"}

      context = %{
        timeout_remaining_ms: 300_000,
        test_mode: true,
        mock_responses: %{
          agent_a: fn _input -> {:ok, %{position: :approve, score: 1.0}} end,
          agent_b: fn _input -> {:ok, %{position: :reject, score: 0.0}} end
        }
      }

      assert {:escalate, %DelegationResult{status: :escalate}} =
               Synapse.coordinate(spec, inputs, context)
    end

    test "returns {:timeout, result} when timeout_ms exceeded" do
      spec = %{
        coordinator: :test_coordinator,
        agents: [:agent_a, :agent_b],
        max_iterations: 100,
        consensus_threshold: 0.8,
        escalation_policy: :on_no_consensus
      }

      inputs = %{data: "test input"}

      context = %{
        timeout_remaining_ms: 0,
        test_mode: true,
        mock_responses: %{
          agent_a: fn _input -> {:ok, %{position: :approve, score: 1.0}} end,
          agent_b: fn _input -> {:ok, %{position: :approve, score: 1.0}} end
        }
      }

      assert {:timeout, %DelegationResult{status: :timeout}} =
               Synapse.coordinate(spec, inputs, context)
    end

    test "returns {:error, :invalid_spec} for invalid synapse_spec" do
      spec = %{
        coordinator: :test_coordinator,
        agents: [],
        max_iterations: 0,
        consensus_threshold: 0.8,
        escalation_policy: :invalid
      }

      assert {:error, :invalid_spec} =
               Synapse.coordinate(spec, %{}, %{timeout_remaining_ms: 1000})
    end

    test "telemetry events emitted at each stage" do
      test_pid = self()

      :telemetry.attach_many(
        "coordinate-test-handler",
        [
          [:synapse, :coordination, :started],
          [:synapse, :iteration, :completed],
          [:synapse, :consensus, :checked],
          [:synapse, :coordination, :completed]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      spec = %{
        coordinator: :test_coordinator,
        agents: [:agent_a],
        max_iterations: 3,
        consensus_threshold: 0.8,
        escalation_policy: :on_no_consensus
      }

      context = %{
        timeout_remaining_ms: 300_000,
        test_mode: true,
        mock_responses: %{
          agent_a: fn _input -> {:ok, %{position: :approve, score: 1.0}} end
        }
      }

      Synapse.coordinate(spec, %{}, context)

      assert_receive {:telemetry, [:synapse, :coordination, :started], _, _}
      assert_receive {:telemetry, [:synapse, :coordination, :completed], _, _}

      :telemetry.detach("coordinate-test-handler")
    end

    test "cost tracking accumulated across iterations" do
      spec = %{
        coordinator: :test_coordinator,
        agents: [:agent_a],
        max_iterations: 3,
        consensus_threshold: 0.8,
        escalation_policy: :on_no_consensus
      }

      context = %{
        timeout_remaining_ms: 300_000,
        test_mode: true,
        mock_responses: %{
          agent_a: fn _input -> {:ok, %{position: :approve, score: 1.0}} end
        }
      }

      assert {:ok, result} = Synapse.coordinate(spec, %{}, context)
      assert result.telemetry.iterations >= 1
    end
  end
end
