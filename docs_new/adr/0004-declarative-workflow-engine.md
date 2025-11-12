# ADR-0004: Declarative Workflow Engine for Multi-Agent Pipelines

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Workflow Team

## Context

`Synapse.Workflows.ChainOrchestrator` (synapse_new/lib/synapse/workflows/chain_orchestrator.ex) hardcodes the executor → critic → LLM pipeline by calling `Jido.Exec.run/3` sequentially with imperative logic. `ReviewOrchestrator` (legacy) duplicates similar control flow. Adding a new step (e.g., human escalation, second LLM) requires editing the module and sprinkling additional logging, telemetry, and error handling. Retries/compensation are handled ad hoc (GenerateCritique embeds compensation metadata, but the orchestrator doesn’t reason about it).

This approach creates several issues:

1. **No reusable execution model.** Every workflow (simple vs. chain vs. integration) re-implements sequencing, error propagation, and audit trails.
2. **Limited configurability.** There’s no declarative way to say, “Run action B only if action A finds issues,” or “Fan out to multiple LLMs and aggregate results.” Everything lives in bespoke code blocks.
3. **Poor observability/introspection.** Because steps are just sequential `with` clauses, we can’t emit structured trace data or inspect pending steps for pausing/resuming.

## Decision

Introduce a declarative Workflow Engine that:

* Represents workflows as data (e.g., a DAG or chain spec) specifying steps, dependencies, retry/compensation policies, and context passing.
* Provides an interpreter module (e.g., `Synapse.Workflow.Engine`) that executes the spec, handles retries/compensation uniformly, and emits telemetry for each step.
* Allows workflows to reference actions, agents, or signal interactions declaratively, enabling reuse across different orchestration patterns.

Example spec (conceptual):

```elixir
%Workflow{
  steps: [
    %{id: :executor, action: Synapse.Actions.Echo, params: %{message: "{{message}}"}},
    %{id: :critic, action: Synapse.Actions.CriticReview, requires: [:executor]},
    %{id: :llm, action: Synapse.Actions.GenerateCritique, requires: [:critic], retry: [max_attempts: 2]}
  ],
  outputs: [:executor, :critic, :llm]
}
```

The engine resolves templates, runs steps, records results, and surfaces a consolidated audit trail.

## Consequences

* `ChainOrchestrator` becomes a thin wrapper that builds a workflow spec and hands it to the engine. Other orchestrators (e.g., human escalation) can do the same.
* Tests gain the ability to instantiate workflows with alternate specs, reducing duplication and making failure scenarios deterministic.
* Future features (branching, parallelism, pause/resume) become extensions to the engine rather than bespoke code.

## Alternatives Considered

1. **Keep imperative orchestrators but extract helper functions.**  
   Rejected because we’d still lack a declarative representation, making persistence/introspection impossible.

2. **Adopt an external workflow engine (Temporal, Oban).**  
   Rejected because Synapse needs tight integration with Jido actions, signal bus, and agent state; external schedulers would add heavy dependencies without understanding our domain semantics.

## Related ADRs

* ADR-0002 (Runtime Kernel) and ADR-0003 (Signal Router) provide the infrastructure the engine will rely on for signal interactions and runtime handles.
* Upcoming ADRs will cover telemetry/audit and human-in-the-loop adapters built on top of the declarative engine.
