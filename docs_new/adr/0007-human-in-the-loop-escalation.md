# ADR-0007: Human-in-the-Loop Escalation & Collaboration

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Experience Team

## Context

Docs (`docs/20251028/multi_agent_framework/vision.md`, `docs/continuation_prompt.md`) describe human escalation patterns (review conflicts, HITL workflows), but the codebase has no concrete implementation. Review summaries include `metadata.escalations`, yet there is no mechanism to pause a workflow, notify a human, collect feedback, and resume. All orchestrators assume fully autonomous completion.

Problems:

1. **No escalation channel.** When specialists disagree or fail, the coordinator emits a failed summary, but there’s no structured path to involve humans.
2. **No state persistence for pauses.** Workflow state lives only in memory; introducing a human step would require persisting context while awaiting input.
3. **UI/adapter gap.** Phoenix endpoints only expose demo pages; there is no API for humans to inspect pending escalations or feed outcomes back.

## Decision

Define a first-class Human-in-the-Loop (HITL) subsystem with:

* **Escalation signals:** Standardized messages (`review.escalation.request`, `review.escalation.response`) routed via Signal Router with payloads describing reason, required action, and resume tokens.
* **Workflow integration:** Declarative workflow specs (ADR-0004) can include `:human_task` steps that pause the engine, persist state, and resume when a matching response arrives.
* **Adapter endpoints:** Provide Phoenix (and optional CLI/API) views where humans can claim escalations, inspect context, and submit responses. Responses publish the corresponding signal with resume info.
* **Timeouts & fallback:** Workflows define escalation timeouts; if no human responds, the engine can abort or take alternative paths.

## Consequences

* Requires persistence layer for workflow state & pending escalations (ETS/DB). At minimum, store serialized workflow context keyed by escalation ID.
* Adds new UI/API surfaces; we must design secure access controls for human collaborators.
* Encourages better separation between workflow execution and presentation logic.

## Alternatives Considered

1. **Handle escalations outside Synapse (manual steps).**  
   Rejected: undermines the goal of cohesive multi-agent orchestration with human collaboration.

2. **Simple email/slack notifications without resume tokens.**  
   Rejected: would not allow workflows to resume deterministically or track audit history.

## Related ADRs

* ADR-0004 (workflow engine) must support paused steps and resume tokens.
* ADR-0006 (observability) will record escalation events for auditing.
