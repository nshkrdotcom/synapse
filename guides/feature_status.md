# Feature Status

Feature claims use these statuses:

- `live`: AppKit-backed, lower owner ready, tested, and StackLab-covered.
- `live-stack-deterministic`: AppKit-backed and lower-runtime-backed with a
  deterministic local runtime adapter; not a live provider claim.
- `fixture-backed`: deterministic fixture path; useful and testable but not a
  live provider/runtime claim.
- `disabled`: surface exists only as denied/disabled product state.
- `roadmap`: not implemented or not tested.

| Feature | Status | Notes |
|---|---|---|
| Installation/bootstrap | fixture-backed | Uses `Synapse.ProductBootstrap.fixture_status/1`; live installation requires an injected/proven AppKit installation surface. |
| Run start | fixture-backed by default; live-stack-deterministic in StackLab slice | `Synapse.AgentRuns.start_run/2` calls `AppKit.AgentIntake` with the fixture backend by default. `mix stack_lab.synapse.live_slice --json` proves explicit AppKit -> Mezzanine AgentLoop start with runtime projection readback. |
| Turn submission | fixture-backed by default; live-stack-deterministic in StackLab slice | `Synapse.Turns.submit_turn/3` calls `AppKit.AgentIntake` with the fixture backend by default. The live slice proves explicit lower-runtime turn acceptance. |
| Await outcome | live-stack-deterministic | `Synapse.AgentRuns.await_run/3` is proven in the StackLab live slice against the AppKit Mezzanine bridge and deterministic AgentLoop. |
| Cancel/refresh | fixture-backed | Cancel routes through agent intake fixture; refresh routes through headless fixture. |
| Review queue/detail/decision | fixture-backed | `Synapse.Reviews` uses an injectable AppKit-shaped review surface. |
| Memory projection | fixture-backed | Uses AppKit DTO construction and redacted projections. |
| Memory feedback write | disabled | Raw memory payloads are rejected; write surface is not claimed live. |
| Context pack | fixture-backed | Product-safe fixture projection; final AppKit context-pack surface remains a lower-stack prerequisite. |
| Tool/model grants | fixture-backed | Read-only AppKit catalog/grant projections. |
| Catalog eligibility | fixture-backed | Includes denied external-write posture. Assignment remains disabled. |
| Teams | fixture-backed | DTO/projection view only. Executable team control is disabled. |
| Arbitration | fixture-backed | Projection view and review-routed final decision fixture. Memory writes are disabled. |
| Runtime projection/evidence receipt | live-stack-deterministic | StackLab live slice proves completed runtime projection, candidate fact refs, memory proof refs, lower receipt ref, and tool action receipt ref. |
| Evidence/replay | fixture-backed | UI evidence, receipt, replay, and missing evidence posture remain projected fixtures. |
| Operations health | fixture-backed | Operational health is separate from trace export. |
| StackLab fixture proof | fixture-backed | `mix stack_lab.synapse.acceptance --json` passes from StackLab. |
| StackLab live run slice | live-stack-deterministic | `mix stack_lab.synapse.live_slice --json` proves run start, turn submit, await, runtime projection, evidence refs, no-bypass, and denied lower-effect non-submission. |

No live provider behavior, production deployment, team execution, memory
feedback write, catalog assignment, or persisted cross-tenant data rejection is
claimed in this branch.
