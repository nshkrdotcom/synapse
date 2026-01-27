defmodule Synapse.Escalation do
  @moduledoc """
  Escalation request building for human review.

  When agents cannot reach consensus after max iterations, builds
  a structured escalation request that FlowStone can route to its
  approval gates.
  """

  @doc """
  Build an escalation request from coordination state.

  ## Parameters

    * `state` - Current coordination state with agent_states and request
    * `reason` - Reason for escalation (e.g., :no_consensus, :always_escalate)

  ## Returns

  A map containing:
    * `:type` - Escalation type (:human_decision, :policy_exception, :expert_review)
    * `:context` - Summary of the coordination attempt
    * `:options` - Options derived from agent positions
    * `:agent_positions` - Map of agent_id to their position
    * `:disagreement_summary` - Human-readable disagreement summary
  """
  @spec build_escalation_request(map(), atom()) :: map()
  def build_escalation_request(state, reason) do
    policy = get_in(state, [:request, :synapse_spec, :escalation_policy]) || reason
    agent_positions = extract_positions(state.agent_states)

    %{
      type: determine_escalation_type(policy),
      context: build_context_summary(state, reason),
      options: derive_options(agent_positions),
      agent_positions: agent_positions,
      disagreement_summary: summarize_disagreement(state.agent_states)
    }
  end

  @doc """
  Map escalation policy to escalation request type.

  ## Mappings

    * `:always_escalate` -> `:human_decision`
    * `:human_approval` -> `:human_decision` (synonym for :always_escalate)
    * `:on_no_consensus` -> `:human_decision`
    * `:on_failure` -> `:policy_exception`
    * `:never_escalate` -> `:policy_exception`
    * Any other value -> `:policy_exception`
  """
  @spec determine_escalation_type(atom()) :: :human_decision | :policy_exception | :expert_review
  def determine_escalation_type(:always_escalate), do: :human_decision
  def determine_escalation_type(:human_approval), do: :human_decision
  def determine_escalation_type(:on_no_consensus), do: :human_decision
  def determine_escalation_type(:on_failure), do: :policy_exception
  def determine_escalation_type(:never_escalate), do: :policy_exception
  def determine_escalation_type(_), do: :policy_exception

  @doc """
  Summarize disagreement between agents.

  Returns a human-readable string describing the disagreement.
  """
  @spec summarize_disagreement(map()) :: String.t()
  def summarize_disagreement(agent_states) when agent_states == %{} do
    "No agent responses available."
  end

  def summarize_disagreement(agent_states) do
    summaries =
      agent_states
      |> Enum.map(fn {agent_id, state} ->
        position = get_in(state, [:output, :position]) || Map.get(state, :status)
        reason = get_in(state, [:output, :reason])

        if reason do
          "#{agent_id}: #{position} (#{reason})"
        else
          "#{agent_id}: #{position}"
        end
      end)
      |> Enum.join("; ")

    "Agent positions: #{summaries}"
  end

  # Extract agent positions from their states
  defp extract_positions(agent_states) do
    agent_states
    |> Enum.into(%{}, fn {agent_id, state} ->
      position = get_in(state, [:output, :position]) || Map.get(state, :status)
      {agent_id, position}
    end)
  end

  # Derive unique options from agent positions
  defp derive_options(agent_positions) do
    agent_positions
    |> Map.values()
    |> Enum.uniq()
    |> Enum.filter(&is_atom/1)
  end

  # Build a context summary string
  defp build_context_summary(state, reason) do
    iteration = Map.get(state, :iteration, 0)
    score = Map.get(state, :consensus_score, 0.0)
    agent_count = map_size(state.agent_states)

    "Coordination #{reason} after #{iteration} iterations with #{agent_count} agents. " <>
      "Final consensus score: #{score || "N/A"}."
  end
end
