defmodule Synapse.DelegationResult do
  @moduledoc """
  Result struct returned from Synapse to FlowStone after coordination.

  Contains the coordination outcome, outputs, telemetry data, and
  optional escalation request for human review.

  ## Status Values

    * `:success` - Coordination completed, outputs are final
    * `:escalate` - Human decision required, escalation_request populated
    * `:timeout` - Time budget exhausted, partial_outputs may be available
    * `:error` - Coordination failed, reason populated

  ## Fields

    * `:status` - Outcome status of the coordination
    * `:outputs` - Final outputs when status is :success
    * `:telemetry` - Telemetry data from the coordination
    * `:reason` - Error/escalation reason atom
    * `:partial_outputs` - Partial results on timeout or escalation
    * `:escalation_request` - Human review request when status is :escalate
  """

  @type t :: %__MODULE__{
          status: :success | :escalate | :timeout | :error,
          outputs: map() | nil,
          telemetry: telemetry_data(),
          reason: atom() | nil,
          partial_outputs: map() | nil,
          escalation_request: escalation_request() | nil
        }

  @type telemetry_data :: %{
          iterations: non_neg_integer(),
          total_tokens: non_neg_integer(),
          total_cost_usd: Decimal.t(),
          agents_invoked: [atom()],
          consensus_score: float() | nil
        }

  @type escalation_request :: %{
          type: :human_decision | :policy_exception | :expert_review,
          context: String.t(),
          options: [atom()],
          agent_positions: map(),
          disagreement_summary: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [
    :status,
    :outputs,
    :telemetry,
    :reason,
    :partial_outputs,
    :escalation_request
  ]

  @doc """
  Creates a new DelegationResult from a map of attributes.

  Returns `{:ok, %DelegationResult{}}` on success or `{:error, reason}` on failure.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    status = Map.get(attrs, :status)

    if status in [:success, :escalate, :timeout, :error] do
      result = struct!(__MODULE__, Map.to_list(attrs))
      {:ok, result}
    else
      {:error, {:invalid_status, status}}
    end
  end
end
