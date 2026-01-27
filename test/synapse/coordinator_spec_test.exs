defmodule Synapse.CoordinatorSpecTest do
  use ExUnit.Case, async: true

  alias Synapse.CoordinatorSpec

  describe "struct" do
    test "valid spec with :round_robin strategy" do
      spec = %CoordinatorSpec{
        id: :debate_coordinator,
        strategy: :round_robin,
        consensus_algorithm: :weighted_vote,
        weights: %{proposer_agent: 0.3, critic_agent: 0.4, synthesizer_agent: 0.3},
        termination_conditions: [{:consensus_reached, threshold: 0.8}]
      }

      assert spec.strategy == :round_robin
    end

    test "valid spec with :parallel strategy" do
      spec = %CoordinatorSpec{
        id: :parallel_coordinator,
        strategy: :parallel,
        consensus_algorithm: :majority,
        weights: %{},
        termination_conditions: [{:max_iterations, count: 3}]
      }

      assert spec.strategy == :parallel
    end

    test "valid spec with :sequential strategy" do
      spec = %CoordinatorSpec{
        id: :sequential_coordinator,
        strategy: :sequential,
        consensus_algorithm: :unanimous,
        weights: %{},
        termination_conditions: [{:timeout, ms: 60_000}]
      }

      assert spec.strategy == :sequential
    end

    test "valid spec with :weighted_vote consensus algorithm" do
      spec = %CoordinatorSpec{
        id: :weighted_coordinator,
        consensus_algorithm: :weighted_vote,
        weights: %{agent_a: 0.6, agent_b: 0.4}
      }

      assert spec.consensus_algorithm == :weighted_vote
    end

    test "valid spec with :unanimous consensus algorithm" do
      spec = %CoordinatorSpec{
        id: :strict_coordinator,
        consensus_algorithm: :unanimous
      }

      assert spec.consensus_algorithm == :unanimous
    end

    test "valid spec with :majority consensus algorithm" do
      spec = %CoordinatorSpec{
        id: :majority_coordinator,
        consensus_algorithm: :majority
      }

      assert spec.consensus_algorithm == :majority
    end

    test "default values applied correctly" do
      spec = %CoordinatorSpec{id: :default_coordinator}

      assert spec.strategy == :parallel
      assert spec.consensus_algorithm == :weighted_vote
      assert spec.weights == %{}
      assert spec.termination_conditions == []
    end
  end

  describe "validate/1" do
    test "passes for valid spec" do
      attrs = %{
        id: :test_coordinator,
        strategy: :parallel,
        consensus_algorithm: :weighted_vote,
        weights: %{agent_a: 0.5, agent_b: 0.5},
        termination_conditions: [{:consensus_reached, threshold: 0.8}]
      }

      assert {:ok, _spec} = CoordinatorSpec.validate(attrs)
    end

    test "weights sum validation - should sum to 1.0" do
      attrs = %{
        id: :test_coordinator,
        strategy: :parallel,
        consensus_algorithm: :weighted_vote,
        weights: %{agent_a: 0.5, agent_b: 0.5},
        termination_conditions: []
      }

      assert {:ok, _spec} = CoordinatorSpec.validate(attrs)
    end

    test "weights sum validation fails when not summing to 1.0" do
      attrs = %{
        id: :test_coordinator,
        strategy: :parallel,
        consensus_algorithm: :weighted_vote,
        weights: %{agent_a: 0.3, agent_b: 0.3},
        termination_conditions: []
      }

      assert {:error, _reason} = CoordinatorSpec.validate(attrs)
    end

    test "empty weights allowed (equal distribution)" do
      attrs = %{
        id: :test_coordinator,
        strategy: :parallel,
        consensus_algorithm: :weighted_vote,
        weights: %{},
        termination_conditions: []
      }

      assert {:ok, _spec} = CoordinatorSpec.validate(attrs)
    end

    test "termination conditions validation" do
      attrs = %{
        id: :test_coordinator,
        strategy: :parallel,
        consensus_algorithm: :weighted_vote,
        weights: %{},
        termination_conditions: [
          {:consensus_reached, threshold: 0.8},
          {:max_iterations, count: 5},
          {:timeout, ms: 300_000},
          {:agent_agreement, agents: [:agent_a, :agent_b]}
        ]
      }

      assert {:ok, spec} = CoordinatorSpec.validate(attrs)
      assert length(spec.termination_conditions) == 4
    end
  end
end
