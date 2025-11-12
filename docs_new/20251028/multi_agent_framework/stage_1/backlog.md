# Stage 1 Backlog

Each line item starts as a failing test. Update this list as tasks land (checkmarks in PR description).

## 0. Foundation

- [x] Spin up `Jido.Signal.Bus` test helper (start/stop functions).
- [x] Add agent registry helpers (`Synapse.AgentRegistry`) for idempotent spawn.
- [x] Scaffold directories (`lib/synapse/agents/*`, `lib/synapse/actions/*`).

## 1. CoordinatorAgent

- [x] **Test**: `classify_change/1` returns `:fast_path` for small, unlabelled diffs.
- [x] **Test**: `classify_change/1` returns `:deep_review` when risk labels present.
- [x] **Test**: Review tracking and specialist result aggregation.
- [x] **Test**: Synthesis generates correct summary structure.
- [x] **Test**: missing specialist results triggers summary with `status: :failed`.

Implementation tasks (execute in order of tests):

- [x] Implement `CoordinatorAgent` module + schema.
- [x] Implement classification logic via `ClassifyChange` action.
- [x] Implement review tracking (start_review, add_specialist_result, complete_review).
- [x] Implement synthesis action invocation.

## 2. SecurityAgent

- [x] **Test**: State helpers (record_history, learn_from_correction, record_failure).
- [x] **Test**: `learn_from_correction/2` updates existing pattern count.
- [x] **Test**: `record_failure/2` preserves max 50 entries.
- [x] **Test**: Has security actions registered.
- [x] Implement module, schema with state management.
- [x] Implement `record_history/2`, `learn_from_correction/2`, `record_failure/2`.

## 3. PerformanceAgent

- [x] Mirror security tests (learned patterns, scar tissue, state helpers).
- [x] Implement action runner + state helpers.

## 4. Security Actions

- [x] **Test**: `CheckSQLInjection` catches interpolated SQL in diff.
- [x] **Test**: validation error on missing `diff`.
- [x] Implement action module + docs.
- [x] Repeat for `CheckXSS`, `CheckAuthIssues` (tests first).

## 5. Performance Actions

- [x] `CheckComplexity` – tests for high cyclomatic complexity detection + validation.
- [x] `CheckMemoryUsage` – tests for greedy enum usage.
- [x] `ProfileHotPath` – tests for runtime metadata.
- [x] Implement corresponding modules.

## 6. Review Summary Action

- [x] Tests for severity aggregation, recommendation creation.
- [x] Implement action used by coordinator.

## 7. Integration Flow

- [x] Write integration test that:
  - simulates complete review workflow with agents and actions,
  - tests classification, specialist execution, and synthesis,
  - validates summary structure and findings.
- [x] Ensure proper test cleanup.

## 8. Documentation & Cleanup

- [x] Code aligns with `architecture.md`, `agents.md`, `actions.md` specifications.
- [x] Run `mix precommit` - all checks pass (151 tests, 0 failures).

---

Add new tasks here when Stage 1 scope grows. Remove items only after merge, never beforehand.***
