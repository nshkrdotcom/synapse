defmodule Synapse.CoordinationState do
  @moduledoc """
  Internal state tracked during multi-agent coordination.

  Maintains the current iteration, agent states, consensus score,
  timeout tracking, and timestamps throughout the coordination loop.

  ## Fields

    * `:request_id` - Unique identifier for this coordination request
    * `:coordinator_spec` - The coordinator specification being used
    * `:iteration` - Current iteration counter (starts at 0)
    * `:agent_states` - Map of agent_id to their current state
    * `:consensus_score` - Current consensus score (nil until calculated)
    * `:elapsed_ms` - Total elapsed time in milliseconds
    * `:timeout_remaining_ms` - Remaining timeout budget
    * `:created_at` - When coordination started
    * `:last_updated_at` - Last state update timestamp
  """

  @type t :: %__MODULE__{
          request_id: String.t(),
          coordinator_spec: Synapse.CoordinatorSpec.t(),
          iteration: non_neg_integer(),
          agent_states: %{atom() => agent_state()},
          consensus_score: float() | nil,
          elapsed_ms: non_neg_integer(),
          timeout_remaining_ms: non_neg_integer(),
          created_at: DateTime.t(),
          last_updated_at: DateTime.t()
        }

  @type agent_state :: %{
          :status => :pending | :running | :complete | :error,
          :output => term(),
          optional(:score) => float(),
          optional(:position) => atom()
        }

  defstruct [
    :request_id,
    :coordinator_spec,
    :iteration,
    :agent_states,
    :consensus_score,
    :elapsed_ms,
    :timeout_remaining_ms,
    :created_at,
    :last_updated_at
  ]

  @doc """
  Creates a new CoordinationState with correct defaults.

  ## Parameters

    * `request_id` - Unique identifier for the coordination request
    * `coordinator_spec` - The CoordinatorSpec to use
    * `timeout_remaining_ms` - Initial timeout budget in milliseconds
  """
  @spec new(String.t(), Synapse.CoordinatorSpec.t(), non_neg_integer()) :: t()
  def new(request_id, coordinator_spec, timeout_remaining_ms) do
    now = DateTime.utc_now()

    %__MODULE__{
      request_id: request_id,
      coordinator_spec: coordinator_spec,
      iteration: 0,
      agent_states: %{},
      consensus_score: nil,
      elapsed_ms: 0,
      timeout_remaining_ms: timeout_remaining_ms,
      created_at: now,
      last_updated_at: now
    }
  end
end
