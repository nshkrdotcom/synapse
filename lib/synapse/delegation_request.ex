defmodule Synapse.DelegationRequest do
  @moduledoc """
  Request struct for FlowStone to delegate agentic execution to Synapse.

  Packages all context needed for Synapse coordination including the
  synapse_spec (agent coordination configuration), inputs from previous
  pipeline steps, resource bindings, and timeout budget.

  ## Fields

    * `:run_id` - FlowStone pipeline run identifier for correlation
    * `:step_id` - Current step identifier for checkpointing
    * `:synapse_spec` - Multi-agent coordination configuration
    * `:inputs` - Data from previous pipeline steps
    * `:context` - FlowStone resource bindings and metadata
    * `:timeout_ms` - Total time budget for coordination
  """

  @type t :: %__MODULE__{
          run_id: String.t(),
          step_id: String.t(),
          synapse_spec: synapse_spec(),
          inputs: map(),
          context: delegation_context(),
          timeout_ms: non_neg_integer()
        }

  @type synapse_spec :: %{
          coordinator: atom() | nil,
          agents: [atom()],
          max_iterations: pos_integer(),
          consensus_threshold: float(),
          escalation_policy: escalation_policy()
        }

  @type escalation_policy ::
          :on_failure
          | :on_no_consensus
          | :always_escalate
          | :never_escalate

  @type delegation_context :: %{
          optional(:agent_runner) => module(),
          optional(:artifact_store) => module(),
          optional(:approval_gate) => module(),
          optional(:git) => module(),
          optional(:progress) => module(),
          optional(:timeout_remaining_ms) => non_neg_integer(),
          optional(:test_mode) => boolean(),
          optional(:mock_responses) => map(),
          optional(atom()) => term()
        }

  @valid_escalation_policies [
    :on_failure,
    :on_no_consensus,
    :always_escalate,
    :never_escalate,
    :human_approval
  ]

  @derive Jason.Encoder
  defstruct [
    :run_id,
    :step_id,
    :synapse_spec,
    :inputs,
    :context,
    :timeout_ms
  ]

  @doc """
  Validates and creates a DelegationRequest from a map of attributes.

  Returns `{:ok, %DelegationRequest{}}` on success or `{:error, reason}` on failure.
  The `:human_approval` escalation policy is normalized to `:always_escalate`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    case validate(attrs) do
      {:ok, validated} -> {:ok, struct!(__MODULE__, Map.to_list(validated))}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates attributes for a DelegationRequest.

  Returns `{:ok, validated_attrs}` on success or `{:error, reason}` on failure.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(attrs) do
    with :ok <- validate_required(attrs, [:run_id, :step_id, :synapse_spec]),
         :ok <- validate_synapse_spec(attrs[:synapse_spec] || attrs["synapse_spec"]) do
      attrs = normalize_escalation_policy(attrs)
      {:ok, attrs}
    end
  end

  defp validate_required(attrs, keys) do
    missing =
      Enum.filter(keys, fn key ->
        is_nil(Map.get(attrs, key)) and is_nil(Map.get(attrs, to_string(key)))
      end)

    case missing do
      [] -> :ok
      keys -> {:error, {:missing_required_fields, keys}}
    end
  end

  defp validate_synapse_spec(nil), do: {:error, {:missing_required_fields, [:synapse_spec]}}

  defp validate_synapse_spec(spec) when is_map(spec) do
    agents = Map.get(spec, :agents, Map.get(spec, "agents", []))
    policy = Map.get(spec, :escalation_policy, Map.get(spec, "escalation_policy"))

    cond do
      agents == [] or agents == nil ->
        {:error, {:invalid_synapse_spec, :agents_required}}

      policy != nil and policy not in @valid_escalation_policies ->
        {:error, {:invalid_synapse_spec, {:invalid_escalation_policy, policy}}}

      true ->
        :ok
    end
  end

  defp validate_synapse_spec(_), do: {:error, {:invalid_synapse_spec, :must_be_map}}

  defp normalize_escalation_policy(attrs) do
    spec = Map.get(attrs, :synapse_spec, Map.get(attrs, "synapse_spec"))

    if is_map(spec) do
      policy = Map.get(spec, :escalation_policy, Map.get(spec, "escalation_policy"))

      if policy == :human_approval do
        updated_spec = Map.put(spec, :escalation_policy, :always_escalate)
        Map.put(attrs, :synapse_spec, updated_spec)
      else
        attrs
      end
    else
      attrs
    end
  end
end
