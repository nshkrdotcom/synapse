# Feature Status

Feature claims use these statuses:

- `live`: AppKit-backed, lower owner ready, tested, and StackLab-covered.
- `fixture-backed`: deterministic fixture path; useful and testable but not a
  live provider/runtime claim.
- `disabled`: surface exists only as denied/disabled product state.
- `roadmap`: not implemented or not tested.

| Feature | Status | Notes |
|---|---|---|
| Installation/bootstrap | fixture-backed | Uses `Synapse.ProductBootstrap.fixture_status/1`; live installation requires an injected/proven AppKit installation surface. |
| Run start | fixture-backed | `Synapse.AgentRuns.start_run/2` calls `AppKit.AgentIntake` with deterministic fixture backend. |
| Turn submission | fixture-backed | `Synapse.Turns.submit_turn/3` calls `AppKit.AgentIntake` with deterministic fixture backend. |
| Cancel/refresh | fixture-backed | Cancel routes through agent intake fixture; refresh routes through headless fixture. |
| Review queue/detail/decision | fixture-backed | `Synapse.Reviews` uses an injectable AppKit-shaped review surface. |
| Memory projection | fixture-backed | Uses AppKit DTO construction and redacted projections. |
| Memory feedback write | disabled | Raw memory payloads are rejected; write surface is not claimed live. |
| Context pack | fixture-backed | Product-safe fixture projection; final AppKit context-pack surface remains a lower-stack prerequisite. |
| Tool/model grants | fixture-backed | Read-only AppKit catalog/grant projections. |
| Catalog eligibility | fixture-backed | Includes denied external-write posture. Assignment remains disabled. |
| Teams | fixture-backed | DTO/projection view only. Executable team control is disabled. |
| Arbitration | fixture-backed | Projection view and review-routed final decision fixture. Memory writes are disabled. |
| Evidence/replay | fixture-backed | Evidence, receipt, replay, and missing evidence posture are projected. |
| Operations health | fixture-backed | Operational health is separate from trace export. |
| StackLab proof | fixture-backed | `mix stack_lab.synapse.acceptance --json` passes from StackLab. |

No live provider behavior, production deployment, or persisted cross-tenant data
rejection is claimed in this branch.
