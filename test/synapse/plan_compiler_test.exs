defmodule Synapse.PlanCompilerTest do
  use ExUnit.Case, async: true

  alias Jido.Plan
  alias Synapse.PlanCompiler
  alias Synapse.TestSupport.PlanCompilerDoubleAction
  alias Synapse.TestSupport.PlanCompilerFetchAction

  test "compiles plan steps into workflow spec with dependencies and metadata" do
    plan =
      Plan.new(context: %{tenant_id: "acme"})
      |> Plan.add(:fetch, {PlanCompilerFetchAction, %{value: 2}})
      |> Plan.add(:double, {PlanCompilerDoubleAction, %{value: 4}}, depends_on: :fetch)

    assert {:ok, spec} = PlanCompiler.compile(plan, name: :demo, plan_version: 2)
    assert spec.name == :demo
    assert spec.metadata.plan_id == plan.id

    fetch = Enum.find(spec.steps, &(&1.id == :fetch))
    double = Enum.find(spec.steps, &(&1.id == :double))

    assert fetch.requires == []
    assert fetch.params == %{value: 2}
    assert fetch.metadata.step_id == plan.steps[:fetch].id
    assert fetch.metadata.action_module == PlanCompilerFetchAction

    assert double.requires == [:fetch]
    assert double.metadata.step_id == plan.steps[:double].id
    assert double.metadata.action_module == PlanCompilerDoubleAction
  end

  test "propagates instruction context and execution options" do
    plan =
      Plan.new(context: %{tenant_id: "acme"})
      |> Plan.add(
        :fetch,
        {PlanCompilerFetchAction, %{value: 3}, %{role: "runner"},
         timeout: 5_000, max_retries: 2, backoff: 50, log_level: :debug}
      )

    assert {:ok, spec} = PlanCompiler.compile(plan, name: :opts_demo)
    [step] = spec.steps

    assert step.context.tenant_id == "acme"
    assert step.context.role == "runner"
    assert step.timeout == 5_000
    assert step.retry.max_attempts == 2
    assert step.retry.backoff == 50
    assert step.opts == [log_level: :debug]
  end
end
