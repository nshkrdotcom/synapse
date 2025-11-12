# Testing Improvements Roadmap

## Current Gaps
- Tests run `async: false`, slowing the suite.
- Limited error-path coverage (missing 429, 5xx, malformed responses).
- No optional integration tests using real provider APIs.

## Objectives
1. Enable async tests where possible.
2. Expand coverage to include critical error scenarios.
3. Provide integration tests gated behind tags/env flags.

## Proposed Changes

### Async Enablement
- Update `Synapse.Actions.ReqLLMActionTest` to `use ExUnit.Case, async: true`.
- Ensure each test case uses unique Req.Test stubs and cleans up process state in `on_exit`.
- Audit shared state (application env) and isolate with `ExUnit.Callbacks.setup_all/2` if needed.

### Error Path Coverage
- Add tests covering:
  - HTTP 429 with Retry-After headers.
  - 500/502/503 responses with provider error bodies.
  - Malformed JSON and empty responses.
  - Transport errors like `:econnrefused`.
- Validate that retries, sanitization, and telemetry behave as expected once implemented.

### Integration Tests
- Introduce `@tag :integration` tests for OpenAI/Gemini behind environment flag (`OPENAI_API_KEY`).
- Default skip unless `mix test --include integration` is used.
- Ensure integration tests respect configurable timeouts and can be run in CI nightly or manually.

## Tooling
- Provide helper module for common test fixtures (payload builders, error stubs).
- Consider property-based tests for prompt composition and sanitization helpers.

## Benefits
- Faster feedback loop, higher confidence in error handling, and ability to detect regressions before deployment.
