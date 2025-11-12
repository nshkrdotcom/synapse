# Synapse LLM Remediation Prompt  
_Path: `docs/20251028/remediation/remediation_prompt.md`_

## Required Reading
1. This prompt _(mandatory every run)_ – `docs/20251028/remediation/remediation_prompt.md`
2. Critique source – `docs/20251028/01_critique_llm_arch.md`
3. Design documents listed in the checklist below (open each before working on its task)

## Context Snapshot
- The critique document enumerates architectural and operational gaps in the current LLM integration.
- The `docs/20251028/remediation/` directory now contains one design brief per remediation area.
- Each brief outlines problem, goals, proposed design, implementation steps, and future work.
- Use this prompt to track progress across all remediation workstreams; update statuses in-place.

## Remediation Checklist & Mapping
| Status | Area | Design Doc |
| --- | --- | --- |
| [x] Observability & telemetry | `docs/20251028/remediation/observability_plan.md` _(implemented with full lifecycle events)_ |
| [x] Timeout policy redesign | `docs/20251028/remediation/timeout_policy.md` _(10min default, per-request overrides)_ |
| [x] Provider adapter refactor | `docs/20251028/remediation/provider_adapter_refactor.md` _(OpenAI & Gemini extracted, ReqLLM is coordinator)_ |
| [x] Response parsing strategy | `docs/20251028/remediation/response_parsing_strategy.md` _(deterministic via provider modules)_ |
| [x] Error sanitization | `docs/20251028/remediation/error_sanitization.md` _(both providers sanitize bodies)_ |
| [x] Resilience & retry policy | `docs/20251028/remediation/resilience_retry_policy.md` _(exponential backoff, configurable, tested)_ |
| [x] Config validation schema | `docs/20251028/remediation/config_validation_schema.md` _(NimbleOptions with helpful errors)_ |
| [x] System prompt strategy | `docs/20251028/remediation/system_prompt_strategy.md` _(explicit shared module with tests)_ |
| [ ] Streaming support | `docs/20251028/remediation/streaming_support.md` |
| [ ] Testing improvements | `docs/20251028/remediation/testing_improvements.md` |
| [ ] Response caching strategy | `docs/20251028/remediation/caching_strategy.md` |
| [ ] Budget tracking | `docs/20251028/remediation/budget_tracking.md` |

### Status Conventions
- Mark progress with GitHub-style checkboxes (`[ ]` → `[x]`).
- Optional shorthand in parentheses after the doc link (e.g., `(PR #123 open)`).
- Add bullet notes beneath the table if a task needs clarification or has blockers.

## Agent Instructions (Run This Every Session)
1. **Read** all entries in Required Reading (refresh context each run).
2. **Review** the checklist and identify the highest-priority unchecked task.
3. **Open & digest** the corresponding design doc plus any linked materials.
4. **Plan & execute** implementation or documentation work as needed.
5. **Update** this prompt:
   - Toggle the checkbox when the task is complete or at a meaningful milestone.
   - Add short bullet notes summarizing current state, open questions, or next steps.
6. **Report** findings or progress back to the user referencing this prompt path.

## Notes & Running Log
- Use this section to capture quick updates, decisions, or TODOs tied to checklist items.
- Example format:
  - `2025-10-28`: Provider adapter design draft reviewed; awaiting stakeholder sign-off.

### 2025-10-28 Session 1

#### Completed
1. **Observability & Telemetry**
   - Added telemetry events to ReqLLM.chat_completion/2:
     - `[:synapse, :llm, :request, :start]` - Emitted at request start
     - `[:synapse, :llm, :request, :stop]` - Emitted on success with duration, token usage
     - `[:synapse, :llm, :request, :exception]` - Emitted on errors
   - Created comprehensive telemetry documentation at `docs/20251028/remediation/telemetry_documentation.md`
   - Includes examples for Logger, metrics collection (Prometheus/StatsD), cost tracking, and TelemetryMetrics integration

2. **Timeout Policy Redesign**
   - Reduced default timeouts from 30 minutes to more reasonable values:
     - `connect_timeout`: 5,000ms (5 seconds)
     - `pool_timeout`: 5,000ms (5 seconds)
     - `receive_timeout`: 600,000ms (10 minutes) - balances reliability with responsiveness
   - Added per-request timeout override support via opts:
     - `:timeout` or `:receive_timeout`
     - `:connect_timeout`
     - `:pool_timeout`
   - Updated module documentation with new timeout options

3. **Provider Adapter Refactor (In Progress)**
   - Created `Synapse.LLMProvider` behaviour defining provider contract:
     - `prepare_body/3` - Build provider-specific request payload
     - `parse_response/2` - Parse provider response into normalized format
     - `translate_error/2` - Convert errors to Jido.Error
     - `supported_features/0` and `default_config/0` (optional callbacks)
   - Implemented `Synapse.Providers.OpenAI` module:
     - Extracted all OpenAI-specific logic from ReqLLM
     - Includes response body sanitization to prevent log bloat
     - Enhanced token usage metadata (prompt/completion/total tokens)
     - Supports all OpenAI features (streaming, json_mode, function_calling, vision)

4. **Provider Adapter Refactor (Completed)**
   - Extracted `Synapse.Providers.Gemini` module:
     - Handles Gemini-specific system_instruction format
     - Role mapping (assistant → model, user → user)
     - Proper handling of safety ratings and content blocking
     - Enhanced token usage metadata
   - Refactored `Synapse.ReqLLM` to act as coordinator:
     - Removed all provider-specific logic (~200 lines)
     - Added `resolve_provider_module/1` with backwards compatibility
     - Delegates payload construction to `provider.prepare_body/3`
     - Delegates response parsing to `provider.parse_response/2`
     - Delegates error translation to `provider.translate_error/2`
   - Fixed error handling in provider parse_response to return tuples
   - All 7 tests passing after refactor

5. **Response Parsing Strategy (Completed)**
   - Removed brittle heuristic detection (checking for "choices" vs "candidates")
   - Response parsing now deterministic based on provider module
   - Each provider owns its response format interpretation
   - Consistent error structures across all providers

6. **Error Sanitization (Completed)**
   - Both OpenAI and Gemini providers sanitize response bodies
   - Truncates bodies >1000 chars to prevent log bloat
   - Removes sensitive data while preserving error details
   - Gemini includes safety_ratings in sanitized errors for debugging

7. **Resilience & Retry Policy (Completed)**
   - Implemented automatic retry with exponential backoff using Req middleware
   - Retries on: HTTP 408 (timeout), 429 (rate limited), 5xx (server errors)
   - Default config: 3 max attempts, 300ms base backoff, 5s max backoff
   - Exponential backoff formula: `base * (2^attempt) + random_jitter`
   - Per-profile configuration via `:retry` option
   - Can disable retries per profile with `enabled: false`
   - Added comprehensive tests verifying retry behavior
   - Tests pass: 9/9 including 2 new retry tests

8. **Config Validation Schema (Completed)**
   - Created Synapse.ReqLLM.Options module with NimbleOptions schemas
   - Validates global config (profiles, default_profile, system_prompt, default_model)
   - Validates profile config (base_url, api_key, model, retry, req_options, etc.)
   - Validates retry config (max_attempts, base_backoff_ms, max_backoff_ms, enabled)
   - Provides helpful error messages on invalid configuration
   - Supports both new profiles format and legacy single-profile format
   - Auto-converts map profiles to keyword lists for validation
   - Added comprehensive tests for missing required fields and invalid values
   - Auto-generated documentation available via Options.docs/0
   - Tests pass: 11/11 including 2 new validation tests

9. **System Prompt Strategy (Completed)**
   - Created `Synapse.ReqLLM.SystemPrompt` shared module
   - Centralized precedence logic (was duplicated in both providers)
   - Three public functions:
     - `resolve/2` - Handles profile > global > default precedence
     - `extract_system_messages/1` - Splits system messages from others
     - `merge/2` - Combines prompts with deduplication (for Gemini)
   - Updated both OpenAI and Gemini providers to use shared module
   - Removed duplicate `resolve_system_prompt/2` functions (~10 lines removed)
   - Added 17 comprehensive unit tests covering all precedence scenarios
   - Added 3 integration tests verifying provider-specific handling
   - Documented precedence explicitly in main ReqLLM module docs
   - Tests pass: 57/57 total (gained 20 system prompt tests)

#### Next Steps
1. (Optional) Improve test coverage (add tests for 429 rate limits, malformed JSON, empty bodies)
2. (Optional) Implement circuit breaker for unhealthy providers
3. (Optional) Add streaming support for long-running generations
4. (Optional) Response caching and budget tracking

#### Notes & Decisions
- Telemetry uses monotonic time for duration measurements (convert to milliseconds for display)
- Request IDs generated using `System.unique_integer/1` converted to base-36 string
- Provider modules determined by `:provider_module` config (falls back to `:payload_format` for backwards compat)
- Per-request timeouts override profile defaults, maintaining flexibility
- Provider behaviour allows new providers without modifying core ReqLLM
- Retry logic uses Req 0.5+ 2-arity callback format (fixed deprecation warnings)
- Retries only on truly transient errors (408, 429, 5xx) - not on auth/validation (4xx)
- Jitter prevents thundering herd problem when many clients retry simultaneously
- All tests pass including retry tests (9/9)

