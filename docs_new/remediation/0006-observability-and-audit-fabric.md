# Remediation Plan – ADR-0006

## Objective

Establish a cohesive observability layer covering telemetry events, tracing context, and audit logging for all Synapse runtimes and workflows.

## Tasks

1. **Context Propagation**
   - [ ] Define a `Synapse.Context` struct (fields: runtime_id, workflow_id, request_id, review_id, correlation_ids).
   - [ ] Pass context through Signal Router messages and workflow execution; ensure every telemetry event includes it.

2. **Telemetry Conventions**
   - [ ] Document event names/fields (e.g., `[:synapse, :workflow, :step, :start]`, `[:synapse, :agent, :crash]`, `[:synapse, :llm, :budget, :trip]`).
   - [ ] Instrument coordinator, specialists, workflow engine, and gateway to emit these events.
   - [ ] Provide helper macros for consistent measurement/metadata maps.

3. **Audit Log Service**
   - [ ] Implement `Synapse.Audit.Store` (ETS or pluggable backend) that records critical lifecycle events.
   - [ ] Expose APIs for querying audit logs (by review_id, workflow_id) for debugging or UI display.
   - [ ] Optional: add persistence hooks so users can push events to their own storage (Kafka, DB).

4. **Tracing / OTEL Integration**
   - [ ] Add optional OpenTelemetry spans for workflow steps and LLM calls; document how to enable exporter.
   - [ ] Ensure spans use the same context IDs as telemetry events.

5. **Dashboards & Alerts**
   - [ ] Provide sample Metrics dashboard definitions (PromEx or LiveDashboard) showing workflow throughput, specialist crash counts, LLM latency/budget.
   - [ ] Document alert thresholds (e.g., repeated specialist crashes, budget trips).

6. **Testing**
   - [ ] Add tests verifying telemetry metadata (context propagation) and audit log entries for key events.
   - [ ] Include property tests ensuring correlation IDs are unique per workflow.

## Verification

* Running workflows emits structured telemetry capturing runtime/workflow IDs; logs are no longer the only source of truth.
* Audit store can answer queries like “what happened to review XYZ?”.
* Optional OTEL exporter produces traces showing coordinator → specialists → LLM gateway spans.

## Risks

* **Performance overhead:** Emitting telemetry/audit events may add latency. Mitigate by making audit logging configurable and leveraging ETS/batch writes.
* **Context plumbing complexity:** Passing context everywhere can clutter APIs. Mitigate by using structs/defaults and helper macros to reduce boilerplate.
