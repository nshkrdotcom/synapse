defmodule Synapse.PlanRunner do
  @moduledoc """
  Executes Jido plans by compiling them into Synapse workflow specs.
  """

  alias Jido.Plan
  alias Synapse.PlanCompiler
  alias Synapse.Workflow.Engine

  @compile_keys [:name, :description, :outputs, :plan_version, :plan_hash, :plan_ref]

  @spec run(Plan.t(), keyword()) :: {:ok, Engine.success_t()} | {:error, Engine.failure_t()}
  def run(plan, opts \\ [])

  def run(%Plan{} = plan, opts) do
    compile_opts = Keyword.take(opts, @compile_keys)
    exec_opts = Keyword.drop(opts, @compile_keys)

    with {:ok, spec} <- PlanCompiler.compile(plan, compile_opts) do
      context = build_context(plan, exec_opts)
      input = Keyword.get(exec_opts, :input, %{})

      exec_opts
      |> Keyword.put(:context, context)
      |> Keyword.put(:input, input)
      |> then(&Engine.execute(spec, &1))
    end
  end

  def run(other, _opts), do: {:error, {:invalid_plan, other}}

  defp build_context(%Plan{} = plan, opts) do
    plan_context = plan.context
    run_context = Keyword.get(opts, :context, %{})

    plan_context
    |> Map.merge(run_context)
    |> Map.put_new(:plan_id, plan.id)
  end
end
