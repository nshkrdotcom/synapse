# Plan Compiler

`Synapse.PlanCompiler` translates `Jido.Plan` DAGs into workflow specs so you can
reuse the `Jido.Plan` builders while still running through
`Synapse.Workflow.Engine`.

## Compile a plan

```elixir
alias Jido.Plan
alias Synapse.PlanCompiler
alias Synapse.Workflow.Engine

plan =
  Plan.new(context: %{tenant_id: "acme"})
  |> Plan.add(:fetch, {MyApp.Actions.Fetch, %{value: 2}})
  |> Plan.add(:double, {MyApp.Actions.Double, %{value: 4}}, depends_on: :fetch)

{:ok, spec} = PlanCompiler.compile(plan, name: :demo_plan, plan_version: "2026-01-07")

{:ok, exec} =
  Engine.execute(spec,
    input: %{},
    context: %{request_id: "req_plan_demo"}
  )
```

## Run in one step

```elixir
alias Jido.Plan
alias Synapse.PlanRunner
alias Synapse.Workflow.Spec

plan =
  Plan.new(context: %{tenant_id: "acme"})
  |> Plan.add(:fetch, {MyApp.Actions.Fetch, %{value: 2}})
  |> Plan.add(:double, {MyApp.Actions.Double, %{value: 4}}, depends_on: :fetch)

{:ok, exec} =
  PlanRunner.run(plan,
    name: :demo_plan,
    outputs: [Spec.output(:result, from: :double, path: [:value])],
    input: %{},
    context: %{request_id: "req_plan_demo"}
  )
```

## Mapping rules

- `depends_on` becomes `requires`
- `max_retries` and `backoff` map to step retry settings
- `timeout` maps to step timeout
- remaining instruction options are passed as `Jido.Exec` options
- plan + instruction context are merged into each step context

## Emissions and context

`Engine.execute/2` emits LineageIR, RunIndex, and Work job events when adapters
are configured. Per-call overrides include `lineage_ir`, `lineage_opts`,
`run_index_adapter`, `run_index_opts`, `work_adapter`, and `work_opts`.

To propagate execution context from signals, pass the extension map
(`Jido.Signal.get_extension(signal, "nsai")`) as the workflow context so
downstream steps inherit run/work/plan metadata.
