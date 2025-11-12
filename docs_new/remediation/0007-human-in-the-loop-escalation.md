# Remediation Plan – ADR-0007

## Objective

Implement first-class human escalation by integrating workflow pause/resume, persistent escalation records, and adapter endpoints for human feedback.

## Tasks

1. **Escalation Signal Contracts**
   - [ ] Define schemas for `review.escalation.request` and `review.escalation.response` (reason, required action, payload snapshot, resume_token).
   - [ ] Extend Signal Router (ADR-0003) to publish/subscribe to these topics with validation.

2. **Workflow Engine Enhancements**
   - [ ] Allow steps to declare `type: :human_task` with timeout and resume handler.
   - [ ] When such a step runs, engine pauses execution, persists context (step results + pending steps) keyed by `resume_token`.
   - [ ] Provide API `Synapse.Workflow.Engine.resume(resume_token, response)` to continue execution once a response arrives.

3. **Persistence Layer**
   - [ ] Implement `Synapse.Escalation.Store` (ETS/db) to persist escalation records (status, assigned_to, timestamps, context).
   - [ ] Ensure data survives coordinator restarts (if ETS, add periodic snapshot / allow custom adapter for persistent stores).

4. **Adapters / UI**
   - [ ] Build Phoenix views/API endpoints to list escalations, show context, and post responses.
   - [ ] Include authorization hooks (at least token-based) so only authorized users can act.
   - [ ] Provide CLI helper for local/manual testing.

5. **Timeout & Fallback Logic**
   - [ ] Workflow engine should handle escalation timeouts (auto-fail, reassign, or fallback path defined in spec).
   - [ ] Emit dedicated telemetry events for escalation lifecycle (created, claimed, resolved, timed out).

6. **Testing**
   - [ ] Add integration tests simulating an escalation (coordinator emits request, test responds, workflow resumes).
   - [ ] Verify persistence/resume after coordinator restart (if practical).

## Verification

* Declarative workflows can include human steps; when executed, engine pauses and resumes reliably.
* Phoenix UI/API displays pending escalations and allows submitting responses.
* Telemetry/audit logs record the full escalation lifecycle.

## Risks

* **State recovery:** If runtime crashes mid-escalation, we must reload pending records. Mitigate by designing the store with replay/resume support.
* **Security:** Human endpoints expose potentially sensitive data. Mitigate with authentication/authorization and redactable fields.
