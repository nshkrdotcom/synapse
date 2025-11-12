# Provider Adapter Refactor (ReqLLM Decomposition)

## Problem Statement
- `Synapse.ReqLLM` currently mixes configuration normalization, payload construction, response parsing, and error translation for all providers.
- Adding or updating a single provider requires editing the core module and respecting implicit branching logic.
- The module size and responsibility set will grow linearly as we add providers such as Claude, Mistral, or local models.

## Goals
1. Introduce a provider abstraction that encapsulates request/response details per provider.
2. Keep `Synapse.ReqLLM` focused on profile resolution, request lifecycle, and shared concerns (timeouts, retries, telemetry).
3. Allow new providers to be added without touching existing ones.
4. Enable per-provider feature flags (e.g., streaming support, native tool invocation).

## High-Level Design

### Behaviour Definition
- Create `Synapse.LLMProvider` behaviour defining callbacks:
  - `build_request(profile_config, params, runtime_config) :: {:ok, Req.Request.t(), request_meta} | {:error, term()}`
  - `prepare_body(profile_config, params, runtime_config) :: map()`
  - `parse_response(response, request_meta) :: {:ok, map()} | {:error, Jido.Error.t()}`
  - `translate_error(error, request_meta) :: Jido.Error.t()`
  - Optional callbacks for streaming or request validation.

### Provider Modules
- Implement `Synapse.Providers.OpenAI` and `Synapse.Providers.Gemini` with current logic lifted out of `Synapse.ReqLLM`.
- Each module owns:
  - Payload/schema translation.
  - Response parsing.
  - Error normalization.
  - Provider-specific defaults (e.g., `system_instruction` for Gemini).

### ReqLLM Coordinator
- `Synapse.ReqLLM` changes:
  - Resolve profile → provider module mapping via configuration (e.g., `%{openai: Synapse.Providers.OpenAI}`).
  - Build a base `Req.Request` with shared headers/timeouts.
  - Delegate payload preparation, response parsing, and error translation to provider module.
  - Manage retries/telemetry centrally.

### Configuration Changes
- Runtime config associates each profile with `:provider_module`.
- Provide sensible defaults (OpenAI/Gemini) to avoid breaking existing configs.
- Ensure schemas validate the presence of `:provider_module` or map to known defaults.

## Open Questions
- How to expose feature flags (streaming, JSON mode) per provider?
- Should providers handle retries or report back to coordinator?
- Strategy for fallback providers or multi-call orchestration.

## Next Steps
1. Define behaviour and migrate existing logic into provider modules.
2. Update tests to exercise provider modules directly as well as end-to-end.
3. Document how to add new providers in developer onboarding.
4. Optionally generate docs for each provider from behaviour metadata.
