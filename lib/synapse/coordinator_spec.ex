defmodule Synapse.CoordinatorSpec do
  @moduledoc """
  Specification for multi-agent coordination strategy.

  Defines how agents are orchestrated, how consensus is calculated,
  and when coordination should terminate.

  ## Fields

    * `:id` - Unique identifier for this coordinator
    * `:strategy` - Agent execution strategy (`:round_robin`, `:parallel`, `:sequential`)
    * `:consensus_algorithm` - Algorithm for consensus calculation
    * `:weights` - Per-agent weights for weighted_vote algorithm
    * `:termination_conditions` - Conditions that end the coordination loop

  ## Strategies

    * `:parallel` - All agents execute concurrently each iteration
    * `:round_robin` - Agents take turns in order
    * `:sequential` - Agents execute one after another within each iteration

  ## Consensus Algorithms

    * `:weighted_vote` - Sum of (agent_weight * agent_score), threshold-based
    * `:unanimous` - All agents must agree (threshold = 1.0)
    * `:majority` - More than half must agree (threshold = 0.5)
  """

  @type t :: %__MODULE__{
          id: atom(),
          strategy: :round_robin | :parallel | :sequential,
          consensus_algorithm: :weighted_vote | :unanimous | :majority,
          weights: %{atom() => float()},
          termination_conditions: [termination_condition()]
        }

  @type termination_condition ::
          {:consensus_reached, [threshold: float()]}
          | {:max_iterations, [count: pos_integer()]}
          | {:timeout, [ms: pos_integer()]}
          | {:agent_agreement, [agents: [atom()]]}

  @valid_strategies [:round_robin, :parallel, :sequential]
  @valid_algorithms [:weighted_vote, :unanimous, :majority]

  defstruct [
    :id,
    strategy: :parallel,
    consensus_algorithm: :weighted_vote,
    weights: %{},
    termination_conditions: []
  ]

  @doc """
  Validates attributes for a CoordinatorSpec.

  Returns `{:ok, %CoordinatorSpec{}}` on success or `{:error, reason}` on failure.
  Validates that weights sum to 1.0 when provided (empty weights are allowed
  for equal distribution).
  """
  @spec validate(map()) :: {:ok, t()} | {:error, term()}
  def validate(attrs) when is_map(attrs) do
    with :ok <- validate_strategy(attrs),
         :ok <- validate_algorithm(attrs),
         :ok <- validate_weights(attrs) do
      spec = struct!(__MODULE__, Map.to_list(attrs))
      {:ok, spec}
    end
  end

  defp validate_strategy(attrs) do
    strategy = Map.get(attrs, :strategy, :parallel)

    if strategy in @valid_strategies do
      :ok
    else
      {:error, {:invalid_strategy, strategy}}
    end
  end

  defp validate_algorithm(attrs) do
    algorithm = Map.get(attrs, :consensus_algorithm, :weighted_vote)

    if algorithm in @valid_algorithms do
      :ok
    else
      {:error, {:invalid_consensus_algorithm, algorithm}}
    end
  end

  defp validate_weights(attrs) do
    weights = Map.get(attrs, :weights, %{})

    cond do
      weights == %{} ->
        :ok

      true ->
        sum = weights |> Map.values() |> Enum.sum()

        if abs(sum - 1.0) < 0.001 do
          :ok
        else
          {:error, {:invalid_weights, :must_sum_to_1, sum}}
        end
    end
  end
end
