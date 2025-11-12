# Workflow Engine Cookbook

ADR-0004 introduced a declarative workflow engine that replaces bespoke
orchestrators with specs. This document explains how to define specs, how the
engine executes them, and how to extend the current chain workflow.

## Core Concepts

- **Specs live in `Synapse.Workflow.Spec`.** A spec bundles `steps`,
  `outputs`, optional metadata, and can be built once and reused.
- **Steps (`Synapse.Workflow.Spec.Step`) encapsulate an action.** Each step
  declares an `id`, `action` module, `params` definition, optional
  `requires` dependencies, human readable labels/descriptions, and retry
  policies (`%{max_attempts: integer, backoff: ms}`).
- **The engine (`Synapse.Workflow.Engine`) interprets the spec.** It applies
  dependencies, handles retries, emits telemetry (`[:synapse, :workflow,
  :step, *]`), and returns structured audit trails.

## Building Specs

Specs can be defined once per module:

```elixir
alias Synapse.Workflow.{Spec, Spec.Step}
alias Synapse.Actions.{Echo, CriticReview, GenerateCritique}

defp workflow_spec do
  Spec.new(
    name: :chain_review,
    description: "Echo -> Critic -> LLM",
    steps: [
      Step.new(id: :echo, action: Echo, params: &__MODULE__.echo_params/1),
      Step.new(
        id: :critic,
        action: CriticReview,
        requires: [:echo],
        params: &__MODULE__.critic_params/1
      ),
      Step.new(
        id: :llm,
        action: GenerateCritique,
        requires: [:critic],
        params: &__MODULE__.llm_params/1
      )
    ],
    outputs: [
      Spec.output(:executor_output, from: :echo),
      Spec.output(:review, from: :critic),
      Spec.output(:suggestion, from: :llm)
    ]
  )
end
```

### Parameter Templating

`params` can be literal maps or functions that receive an environment map:

```elixir
def critic_params(env) do
  %{
    code: Map.fetch!(env.input, :message),
    intent: Map.fetch!(env.input, :intent),
    constraints: Map.get(env.input, :constraints, [])
  }
end
```

The environment exposes:

| Key        | Description                                  |
| ---------- | -------------------------------------------- |
| `:input`   | Original params passed to `Engine.execute/2` |
| `:results` | Map of prior step results (`%{id => value}`) |
| `:context` | Arbitrary context map (request IDs, etc.)    |
| `:workflow`| The spec struct (useful for metadata)        |
| `:step`    | Current `Step` struct                        |

Use these helpers to branch, call helpers, or inject runtime metadata without
manually threading arguments.

### Outputs

`Spec.output/2` maps step results into the response shape. Optional `:path`
plucks nested values, and `:transform` can post-process results. Example:

```elixir
Spec.output(:confidence, from: :critic, path: [:confidence])
```

### Handling Step Errors

Each step halts the workflow when it exhausts its retries by default. For
best-effort steps (like orchestrator specialists) you can set
`on_error: :continue`:

```elixir
Step.new(
  id: :security_scan,
  action: Synapse.Actions.Security.CheckSQLInjection,
  params: & &1.input,
  on_error: :continue
)
```

When the action still fails, the engine records an audit entry with `status: :error`,
stores `%{status: :error, error: reason}` in `exec.results.security_scan`, and keeps
running dependent steps. This enables workflows to consolidate partial findings
without losing telemetry or persistence snapshots.

## Executing Specs

```elixir
context = %{request_id: ChainHelpers.generate_request_id()}

case Synapse.Workflow.Engine.execute(workflow_spec(), input: params, context: context) do
  {:ok, %{outputs: outputs, audit_trail: audit}} ->
    %{executor_output: outputs.executor_output, audit: audit}

  {:error, failure} ->
    {:error, failure.error}
end
```

> **Persistence note:** The engine now persists snapshots via the configured
> adapter (Postgres by default). Provide a `:request_id` either directly in the
> options (`Engine.execute(spec, request_id: "abc", ...)`) or inside the
> `context` map as shown above. Pass `persistence: nil` to `execute/2` when you
> need an in-memory run (e.g., certain unit tests).

`audit_trail` includes workflow metadata, start/finish times, and step-level
entries (status, attempts, duration). On failure the engine returns partial
results and the failing step, allowing future pause/resume implementations to
persist and resume executions.

## Branching & Escalation Example

Branching is expressed via `requires` and conditional `params`:

```elixir
Step.new(
  id: :route,
  action: Synapse.Actions.DecideRoute,
  requires: [:critic],
  params: fn env ->
    review = env.results.critic
    %{severity: review.severity, reviewers: env.input.reviewers}
  end
),
Step.new(
  id: :human_escalation,
  action: Synapse.Actions.NotifyHuman,
  requires: [:route],
  params: fn env ->
    %{enabled?: env.results.route.escalate?, payload: env.input}
  end,
  metadata: %{channel: :slack}
)
```

The notification step runs only if the routing step completes; any additional
automation (e.g., fan-out to multiple agents) can be expressed as parallel
steps that only depend on `:critic`.

## Telemetry & Testing

- Telemetry events (`start`, `stop`, `exception`) fire per step with metadata
  (`workflow`, `step`, `action`, `attempt`, optional `error`). Attach handlers
  in tests to assert instrumentation.
- `Synapse.Workflow.EngineTest` exercises sequential execution, dependency
  ordering, retries, and error surfacing. Use it as a template for future specs.

## Coordinator Workflows

The coordinator stack now rides on dedicated specs:

- `Synapse.Workflows.ReviewClassificationWorkflow` wraps
  `Synapse.Actions.Review.ClassifyChange`, so fast-path vs deep-review decisions
  emit workflow telemetry and snapshots keyed by the review’s request ID.
- `Synapse.Workflows.ReviewSummaryWorkflow` wraps
  `Synapse.Actions.Review.GenerateSummary`, giving the synthesized
  `review.summary` payload the same retries/audit/persistence guarantees.

CoordinatorAgentServer generates deterministic request IDs
(`#{review_id}-classification`, `#{review_id}-summary`, `#{review_id}-fast_path`)
when calling Critic/summary specs, so the Postgres `workflow_executions` table
captures the end-to-end lifecycle. The supervised specialists
(`SecurityAgentServer`, `PerformanceAgentServer`) also invoke their respective
workflows with review-scoped IDs, which means Stage 0 demos, Stage 2
orchestration, and ad-hoc incident flows all share the common engine behavior
instead of bespoke sequencing.

## Next Steps

1. Migrate additional orchestrators by defining specs and delegating to the
   engine (similar to `ChainOrchestrator`).
2. Layer higher-level DSL helpers (e.g., spec builders for common review flows).
3. Persist the `results` map between runs to unlock true pause/resume per ADR.
