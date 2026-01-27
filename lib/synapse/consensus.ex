defmodule Synapse.Consensus do
  @moduledoc """
  Consensus calculation algorithms for multi-agent coordination.

  Provides three consensus algorithms:

    * `:weighted_vote` - Sum of (agent_weight * agent_score), threshold-based
    * `:unanimous` - All agents must agree (score = 1.0 only if all scores are 1.0)
    * `:majority` - Proportion of agents with score > 0.5

  ## Examples

      # Weighted vote with explicit weights
      agent_states = %{
        agent_a: %{score: 1.0},
        agent_b: %{score: 0.0}
      }
      weights = %{agent_a: 0.6, agent_b: 0.4}
      Consensus.calculate_consensus(agent_states, :weighted_vote, weights)
      #=> 0.6

      # Unanimous requires all scores to be 1.0
      Consensus.calculate_consensus(agent_states, :unanimous, %{})
      #=> 0.0

      # Majority counts proportion with score > 0.5
      Consensus.calculate_consensus(agent_states, :majority, %{})
      #=> 0.5
  """

  @doc """
  Calculate consensus score across agent states using the specified algorithm.

  ## Parameters

    * `agent_states` - Map of agent_id to agent state (must contain `:score` key)
    * `algorithm` - One of `:weighted_vote`, `:unanimous`, `:majority`
    * `weights` - Map of agent_id to weight (for `:weighted_vote`). Empty map
      uses equal distribution.

  ## Returns

  A float between 0.0 and 1.0 representing the consensus score.
  """
  @spec calculate_consensus(map(), atom(), map()) :: float()
  def calculate_consensus(agent_states, _algorithm, _weights) when agent_states == %{} do
    0.0
  end

  def calculate_consensus(agent_states, :weighted_vote, weights) do
    effective_weights = resolve_weights(agent_states, weights)

    agent_states
    |> Enum.reduce(0.0, fn {agent_id, state}, acc ->
      score = Map.get(state, :score, 0.0)
      weight = Map.get(effective_weights, agent_id, 0.0)
      acc + weight * score
    end)
  end

  def calculate_consensus(agent_states, :unanimous, _weights) do
    all_agree =
      agent_states
      |> Map.values()
      |> Enum.all?(fn state -> Map.get(state, :score, 0.0) == 1.0 end)

    if all_agree, do: 1.0, else: 0.0
  end

  def calculate_consensus(agent_states, :majority, _weights) do
    total = map_size(agent_states)

    if total == 0 do
      0.0
    else
      agreeing =
        agent_states
        |> Map.values()
        |> Enum.count(fn state -> Map.get(state, :score, 0.0) > 0.5 end)

      agreeing / total
    end
  end

  @doc """
  Check if consensus has been reached based on score and threshold.

  ## Parameters

    * `score` - Current consensus score (0.0 to 1.0)
    * `threshold` - Required threshold for consensus

  ## Returns

  `true` if score >= threshold, `false` otherwise.
  """
  @spec consensus_reached?(float(), float()) :: boolean()
  def consensus_reached?(score, threshold) do
    score >= threshold
  end

  # When no weights provided, distribute equally across all agents
  defp resolve_weights(agent_states, weights) when weights == %{} do
    count = map_size(agent_states)

    if count == 0 do
      %{}
    else
      equal_weight = 1.0 / count

      agent_states
      |> Map.keys()
      |> Enum.into(%{}, fn agent_id -> {agent_id, equal_weight} end)
    end
  end

  defp resolve_weights(_agent_states, weights), do: weights
end
