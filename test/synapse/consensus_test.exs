defmodule Synapse.ConsensusTest do
  use ExUnit.Case, async: true

  alias Synapse.Consensus

  describe "calculate_consensus/3 - weighted_vote" do
    test "calculates score correctly" do
      agent_states = %{
        agent_a: %{status: :complete, output: %{approved: true}, score: 1.0},
        agent_b: %{status: :complete, output: %{approved: true}, score: 1.0},
        agent_c: %{status: :complete, output: %{approved: false}, score: 0.0}
      }

      weights = %{agent_a: 0.3, agent_b: 0.4, agent_c: 0.3}

      # 0.3 * 1.0 + 0.4 * 1.0 + 0.3 * 0.0 = 0.7
      score = Consensus.calculate_consensus(agent_states, :weighted_vote, weights)
      assert_in_delta score, 0.7, 0.001
    end

    test "returns 0.0 when no agent responses" do
      score = Consensus.calculate_consensus(%{}, :weighted_vote, %{})
      assert score == 0.0
    end

    test "handles missing weights - uses equal distribution" do
      agent_states = %{
        agent_a: %{status: :complete, output: %{approved: true}, score: 1.0},
        agent_b: %{status: :complete, output: %{approved: true}, score: 1.0}
      }

      # No weights provided, should distribute equally: 0.5 * 1.0 + 0.5 * 1.0 = 1.0
      score = Consensus.calculate_consensus(agent_states, :weighted_vote, %{})
      assert_in_delta score, 1.0, 0.001
    end
  end

  describe "calculate_consensus/3 - unanimous" do
    test "requires all agents to agree (threshold = 1.0)" do
      agent_states = %{
        agent_a: %{status: :complete, output: %{approved: true}, score: 1.0},
        agent_b: %{status: :complete, output: %{approved: true}, score: 1.0}
      }

      score = Consensus.calculate_consensus(agent_states, :unanimous, %{})
      assert score == 1.0
    end

    test "returns 0.0 if any agent disagrees" do
      agent_states = %{
        agent_a: %{status: :complete, output: %{approved: true}, score: 1.0},
        agent_b: %{status: :complete, output: %{approved: false}, score: 0.0}
      }

      score = Consensus.calculate_consensus(agent_states, :unanimous, %{})
      assert score == 0.0
    end
  end

  describe "calculate_consensus/3 - majority" do
    test "requires >50% agreement" do
      agent_states = %{
        agent_a: %{status: :complete, score: 1.0},
        agent_b: %{status: :complete, score: 1.0},
        agent_c: %{status: :complete, score: 0.0}
      }

      # 2/3 agree = 0.667
      score = Consensus.calculate_consensus(agent_states, :majority, %{})
      assert_in_delta score, 2 / 3, 0.001
    end
  end

  describe "consensus_reached?/2" do
    test "consensus reached when score >= threshold" do
      assert Consensus.consensus_reached?(0.85, 0.8) == true
      assert Consensus.consensus_reached?(0.8, 0.8) == true
      assert Consensus.consensus_reached?(1.0, 0.8) == true
    end

    test "consensus not reached when score < threshold" do
      assert Consensus.consensus_reached?(0.79, 0.8) == false
      assert Consensus.consensus_reached?(0.0, 0.8) == false
      assert Consensus.consensus_reached?(0.5, 0.8) == false
    end
  end
end
