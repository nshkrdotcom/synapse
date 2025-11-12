defmodule Synapse.Workflows.CriticWorkflow do
  @moduledoc """
  Lightweight orchestrator for fast-path critic reviews.

  The workflow evaluates a change with `Synapse.Actions.CriticReview`, then runs
  the result through `Synapse.Actions.Review.DecideEscalation` to determine if
  the change should be auto-approved or escalated to a human reviewer.
  """

  alias Synapse.Actions.CriticReview
  alias Synapse.Actions.Review.DecideEscalation
  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step
  alias Synapse.Workflows.ChainHelpers

  @type input :: %{
          required(:code) => String.t(),
          required(:intent) => String.t(),
          optional(:constraints) => [String.t()],
          optional(:metadata) => map(),
          optional(:escalation_threshold) => float()
        }

  @spec evaluate(input(), keyword()) :: {:ok, map()} | {:error, Jido.Error.t()}
  def evaluate(input, opts \\ [])

  def evaluate(%{code: _code, intent: _intent} = input, opts) do
    context = Keyword.get(opts, :context, %{request_id: ChainHelpers.generate_request_id()})

    engine_opts =
      opts
      |> Keyword.put(:context, context)
      |> Keyword.put(:input, input)

    case Engine.execute(workflow_spec(), engine_opts) do
      {:ok, exec} -> {:ok, build_response(exec, context)}
      {:error, failure} -> {:error, failure.error}
    end
  end

  def evaluate(_invalid_input, _opts) do
    {:error,
     Jido.Error.validation_error(
       "Invalid input: code and intent are required",
       %{required: [:code, :intent]}
     )}
  end

  defp build_response(result, context) do
    %{
      request_id: context.request_id,
      review: result.outputs.review,
      decision: result.outputs.decision,
      escalate?: result.outputs.escalate?,
      reason: result.outputs.reason,
      audit_trail: result.audit_trail
    }
  end

  defp workflow_spec do
    Spec.new(
      name: :critic_workflow,
      description: "Critic review with escalation decision",
      metadata: %{version: 1},
      steps: [critic_step(), decision_step()],
      outputs: [
        Spec.output(:review, from: :critic),
        Spec.output(:decision, from: :decision),
        Spec.output(:escalate?, from: :decision, path: [:escalate?]),
        Spec.output(:reason, from: :decision, path: [:reason])
      ]
    )
  end

  defp critic_step do
    Step.new(
      id: :critic,
      action: CriticReview,
      label: "Critic Review",
      params: fn env ->
        %{
          code: Map.fetch!(env.input, :code),
          intent: Map.fetch!(env.input, :intent),
          constraints: Map.get(env.input, :constraints, [])
        }
      end
    )
  end

  defp decision_step do
    Step.new(
      id: :decision,
      action: DecideEscalation,
      label: "Escalation Decision",
      requires: [:critic],
      params: fn env ->
        %{
          review: Map.fetch!(env.results, :critic),
          threshold: Map.get(env.input, :escalation_threshold, 0.7),
          metadata: Map.get(env.input, :metadata, %{})
        }
      end
    )
  end
end
