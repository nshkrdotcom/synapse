defmodule Synapse.PlanCompiler do
  @moduledoc """
  Compiles Jido plans into Synapse workflow specs.
  """

  alias Jido.{Instruction, Plan}
  alias Jido.Plan.PlanInstruction
  alias Synapse.Workflow.Spec
  alias Synapse.Workflow.Spec.Step

  @spec compile(Plan.t(), keyword()) :: {:ok, Spec.t()} | {:error, term()}
  def compile(plan, opts \\ [])

  def compile(%Plan{} = plan, opts) do
    steps =
      plan.steps
      |> Enum.map(fn {_name, step} -> build_step(plan, step, opts) end)

    spec =
      Spec.new(
        name: Keyword.get(opts, :name, :plan),
        description: Keyword.get(opts, :description),
        metadata: build_metadata(plan, opts),
        steps: steps,
        outputs: Keyword.get(opts, :outputs, [])
      )

    {:ok, spec}
  end

  def compile(other, _opts), do: {:error, {:invalid_plan, other}}

  defp build_step(%Plan{} = plan, %PlanInstruction{} = step, opts) do
    %Instruction{} = instruction = step.instruction
    action = instruction.action

    {retry, exec_opts, timeout} = extract_exec_options(instruction.opts || [])

    Step.new(
      id: step.name,
      action: action,
      params: instruction.params,
      requires: step.depends_on,
      timeout: timeout,
      retry: retry,
      opts: exec_opts,
      context: instruction.context || %{},
      metadata: build_step_metadata(plan, step, instruction, opts)
    )
  end

  defp build_metadata(%Plan{} = plan, opts) do
    %{}
    |> Map.put(:plan_id, plan.id)
    |> maybe_put(:plan_version, Keyword.get(opts, :plan_version))
    |> maybe_put(:plan_hash, Keyword.get(opts, :plan_hash))
    |> maybe_put(:plan_ref, Keyword.get(opts, :plan_ref))
  end

  defp build_step_metadata(
         %Plan{} = plan,
         %PlanInstruction{} = step,
         %Instruction{} = instruction,
         opts
       ) do
    action = instruction.action

    %{}
    |> Map.put(:plan_id, plan.id)
    |> Map.put(:step_id, step.id)
    |> Map.put(:step_key, step.name)
    |> Map.put(:action_module, action)
    |> Map.put(:action_name, action_name(action))
    |> Map.put(:plan_opts, step.opts)
    |> Map.put(:instruction_opts, instruction.opts)
    |> maybe_put(:plan_version, Keyword.get(opts, :plan_version))
    |> maybe_put(:plan_hash, Keyword.get(opts, :plan_hash))
    |> maybe_put(:plan_ref, Keyword.get(opts, :plan_ref))
  end

  defp extract_exec_options(opts) do
    max_retries = Keyword.get(opts, :max_retries)
    backoff = Keyword.get(opts, :backoff)
    timeout = Keyword.get(opts, :timeout)

    retry =
      if is_nil(max_retries) and is_nil(backoff) do
        nil
      else
        %{max_attempts: max_retries || 1, backoff: backoff || 0}
      end

    exec_opts = Keyword.drop(opts, [:max_retries, :backoff, :timeout])

    {retry, exec_opts, timeout}
  end

  defp action_name(action) do
    if function_exported?(action, :name, 0), do: action.name(), else: inspect(action)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
