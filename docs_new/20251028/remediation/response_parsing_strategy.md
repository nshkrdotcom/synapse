# Response Parsing Strategy

## Problem Statement
- Current response parsing relies on heuristics (`choices` vs `candidates`) to detect provider types.
- This approach breaks when providers share field names or evolve their schemas.
- Response parsing is tightly coupled to request handling and bypasses the resolved `profile_name`.

## Goals
1. Make response parsing deterministic based on the resolved provider module.
2. Support multiple response formats per provider (e.g., streaming vs. non-streaming).
3. Provide consistent metadata output for downstream consumers (tokens, finish reason).

## Proposed Design
- After introducing provider adapters (see `provider_adapter_refactor.md`), move parsing responsibilities into the provider modules.
- Provider modules return normalized results in a shared struct/map (e.g., `%{content: binary, metadata: %{...}}`).
- Coordinator (`Synapse.ReqLLM`) should pass `profile_name` and any request metadata into the provider module to aid parsing.
- Errors should include provider hints but avoid leaking raw response bodies (see error sanitization design).

## Implementation Steps
1. Define a `Synapse.LLMResponse` struct with fields: `content`, `metadata`, optionally `raw`.
2. Update provider modules to implement `parse_response/2` returning `{ :ok, %LLMResponse{} }` or `{:error, Jido.Error.t()}`.
3. Remove heuristic `cond` from `Synapse.ReqLLM`.
4. Expand tests to cover multiple provider responses and malformed bodies.

## Future Enhancements
- Provide optional debug logs for mismatched response schemas.
- Support partial response parsing for streaming events (chunk-by-chunk).
