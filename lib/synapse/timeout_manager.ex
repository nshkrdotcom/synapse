defmodule Synapse.TimeoutManager do
  @moduledoc """
  Timeout budget management for coordination loops.

  Propagates FlowStone's timeout budget across Synapse coordination
  iterations, ensuring per-iteration budgets and capturing partial
  state on timeout.
  """

  @doc """
  Calculate per-iteration timeout based on remaining budget.

  Distributes remaining time evenly across remaining iterations.

  ## Parameters

    * `remaining_ms` - Remaining timeout budget in milliseconds
    * `max_iterations` - Total maximum iterations configured
    * `current_iteration` - Current iteration number (1-based)

  ## Returns

  Timeout in milliseconds for the current iteration.
  """
  @spec per_iteration_timeout(non_neg_integer(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  def per_iteration_timeout(remaining_ms, max_iterations, current_iteration) do
    remaining_iterations = max_iterations - current_iteration + 1
    remaining_iterations = max(remaining_iterations, 1)
    div(remaining_ms, remaining_iterations)
  end

  @doc """
  Check if coordination should terminate due to timeout.

  ## Parameters

    * `state` - Map with `:timeout_remaining_ms`, `:elapsed_ms`, and `:timeout_ms` keys

  ## Returns

    * `:continue` - Time remains, continue coordination
    * `{:timeout, partial_state}` - Budget exhausted, returns captured partial state
  """
  @spec should_terminate?(map()) :: :continue | {:timeout, map()}
  def should_terminate?(state) do
    cond do
      state.timeout_remaining_ms <= 0 ->
        {:timeout, capture_partial_state(state)}

      Map.get(state, :timeout_ms, :infinity) != :infinity and
          state.elapsed_ms >= state.timeout_ms ->
        {:timeout, capture_partial_state(state)}

      true ->
        :continue
    end
  end

  @doc """
  Capture current coordination state for partial result on timeout.

  ## Parameters

    * `state` - Current coordination state map

  ## Returns

  Map with iteration, agent_states, consensus_score, and elapsed_ms.
  """
  @spec capture_partial_state(map()) :: map()
  def capture_partial_state(state) do
    %{
      iteration: Map.get(state, :iteration, 0),
      agent_states: Map.get(state, :agent_states, %{}),
      consensus_score: Map.get(state, :consensus_score),
      elapsed_ms: Map.get(state, :elapsed_ms, 0)
    }
  end
end
