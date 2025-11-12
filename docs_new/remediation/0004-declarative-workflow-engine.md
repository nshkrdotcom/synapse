# Remediation Plan – ADR-0004

## Objective

Replace bespoke orchestrator modules with a declarative Workflow Engine that executes action/agent steps based on specs, providing uniform retries, compensation, and telemetry.

## Tasks

1. **Workflow Spec Definition**
   - [x] Define a `Synapse.Workflow.Spec` struct (steps, dependencies, params/template expressions, retry policies, outputs).
   - [x] Support both sequential chains and simple DAGs (dependencies list). Include metadata for audit trails (step labels, descriptions).

2. **Engine Implementation**
   - [x] Build `Synapse.Workflow.Engine` that accepts a spec plus initial context, executes steps, handles retries/compensation based on action metadata, and returns `{status, results, audit_trail}`.
   - [x] Integrate telemetry events (`[:synapse, :workflow, :step, :start/stop/exception]`).
   - [x] Provide hooks for pausing/resuming (engine stores per-step results/audit metadata so executions can be resumed once ADR-0006 lands).

3. **Adapter Layer**
   - [x] Refactor `ChainOrchestrator` to build the existing executor→critic→LLM spec and execute it via the engine.
   - [x] Maintain backwards-compatible return shape (`%{executor_output, review, suggestion, audit_trail}`) by mapping engine results.
   - [x] Deprecate `ReviewOrchestrator` or convert it to a spec as well (now delegates to `ChainOrchestrator`).

4. **Testing & Fixtures**
   - [x] Add unit tests for the engine (success path, retry/failure, dependency enforcement).
   - [x] Update workflow tests (`test/synapse/workflows/*.exs`) to assert on spec execution rather than imperative code.

5. **Docs & Examples**
   - [x] Document how to define custom workflow specs, including parameter templating and branching (`docs/workflows/engine.md`).
   - [x] Provide a cookbook example (e.g., “Add a human escalation step after critic review”) demonstrating the data-driven approach (see branching section in the new doc).

## Verification

* `ChainOrchestrator.evaluate/1` delegates entirely to the workflow engine; no residual imperative sequencing remains.
* Specs can be serialized (e.g., for logging or future persistence).
* Tests cover at least: simple sequential workflow, branching dependency, retry/compensation scenario, and failure propagation.
* CoordinatorAgent classification and synthesis run through `Synapse.Workflows.ReviewClassificationWorkflow` / `ReviewSummaryWorkflow`, so fast-path decisions and summaries emit the same telemetry/persistence snapshots as other workflows.
* Security and performance specialists (and the Stage 0/2 demo flows built on them) funnel their action suites through workflow specs with propagated `request_id`s, so each incident review shares the engine’s retries, audit trail, and Postgres persistence layer.
* Orchestrator-managed agents (runtime configs) now execute their action lists via workflow specs using `on_error: :continue`, so each specialist step persists audit data even when a check fails, and result builders receive structured `{:ok | :error, module, payload}` tuples instead of ad-hoc Exec chains.

## Risks

* **Learning curve:** Developers must learn the spec DSL. Mitigate with clear documentation and helper builders for common patterns.
* **Refactor scope:** Engine introduction touches orchestrators, tests, and actions with retry metadata. Mitigate by piloting with `ChainOrchestrator` first, then migrating others incrementally.
