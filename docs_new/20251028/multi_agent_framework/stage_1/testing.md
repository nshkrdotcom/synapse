# Stage 1 Testing Strategy

We build the MVP entirely with TDD. Every feature begins as a failing test tied directly to an item in `backlog.md`.

## Test Matrix

| Layer | Test File(s) | Purpose |
| --- | --- | --- |
| Actions | `test/synapse/actions/security/*_test.exs`<br>`test/synapse/actions/performance/*_test.exs`<br>`test/synapse/actions/review/*_test.exs` | Validate schemas, happy path outputs, error cases. |
| Specialist Agents | `test/synapse/agents/security_agent_test.exs`<br>`test/synapse/agents/performance_agent_test.exs` | Verify state updates, directive handling, result emission. |
| Coordinator Agent | `test/synapse/agents/coordinator_agent_test.exs` | Classifier logic, directive issuance, multi-agent coordination, summary generation. |
| Signal Integration | `test/synapse/integration/review_signal_flow_test.exs` | Publish `review.request`; assert `review.summary` and intermediate results using bus snapshots. |
| Regression Harness | `mix precommit` | Format, credo, dialyzer, ExUnit (78+ tests). |

## Action Tests

For each new action:

1. **Schema Validation** – ensure missing/invalid fields return `{:error, %Jido.Action.Error{type: :validation_error}}`.
2. **Happy Path** – realistic diff snippet → expected findings and confidence range.
3. **Edge Cases** – empty diff, unsupported language; must not crash.

Use fixture helpers under `test/support/action_fixtures.ex` for diff payloads.

## Agent Tests

### Specialist Agents

- Use `JidoTest.AgentCase`.
- Tests cover:
  - `learn_from_correction/2` adds or updates pattern.
  - `record_failure/2` caps `scar_tissue` to 50 entries.
  - Directive handling triggers action execution (mock heavy actions if necessary).
  - Emitted `review.result` matches schema in `signals.md`.

### Coordinator Agent

- Stub specialist agents via test registry entries or use actual modules in sandbox.
- Key scenarios:
  1. `fast_path` classification (only run minimal checks).
  2. `deep_review` classification (all specialists engaged).
  3. Missing specialist response triggers `status: :failed`.
  4. Final summary merges findings sorted by severity.

## Signal Flow Integration

`review_signal_flow_test.exs` steps:

1. Start `Jido.Signal.Bus` under test supervision (`start_supervised!`).
2. Start coordinator + specialists with test registry.
3. Publish `review.request`.
4. Await `review.summary` via `Jido.Signal.Bus.replay/3` or `has_signal?(bus, ...)`.
5. Assert:
   - Both `review.result` signals exist.
   - Summary severity equals max severity.
   - `active_reviews` cleaned up.

Use `LazyHTML` only when introspecting LiveView (not required here unless we add UI).

## Test Data Management

- Fixture diffs: `test/support/fixtures/diff_samples.ex`.
- Metadata helpers: `test/support/factory.ex`.
- Use deterministic timestamps with `DateTime.from_unix!(123_456_789, :millisecond)`.

## CI Hooks

- `mix test` runs as part of `mix precommit`.
- Add targeted runs for fast feedback:
  - `mix test test/synapse/actions/security` before touching security actions.
  - `mix test test/synapse/agents/coordinator_agent_test.exs` after coordination changes.
- Dialyzer should remain cached; new modules must have typespecs (at least `@type t :: %__MODULE__{}` for agent state).

## Coverage Expectations

- Actions: ≥2 scenarios per action (happy + failure).
- Agents: Branch coverage on classification, response aggregation.
- Integration: Single end-to-end ensures contract alignment.
- Total new tests: expect ~25–30 to land Stage 1.

---

Do not merge until all tests described here exist and pass. Keep this document updated when new scenarios emerge.***
