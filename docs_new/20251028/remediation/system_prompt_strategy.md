# System Prompt Strategy

## Problem Statement
- System prompts can be defined at multiple levels (global, profile, message list), leading to unclear precedence rules.
- Gemini payload handling differs from OpenAI, requiring special merging logic.
- Inconsistent configuration increases the risk of unexpected behavior during prompt orchestration.

## Goals
1. Establish a single, documented precedence order for system prompts.
2. Provide helper functions to compose prompt stacks for all providers.
3. Allow workflows to override or append system instructions deterministically.

## Proposed Precedence
1. Request-level overrides (params/messages provided by caller).
2. Profile-level default prompt (from runtime config).
3. Global default (`@default_system_prompt`).

If a provider does not support explicit system prompts, convert them into user-prefixed content or metadata depending on API capabilities.

## Implementation Outline
- Introduce `Synapse.ReqLLM.SystemPrompts` helper module with:
  - `compose(profile_config, params, runtime_config) :: %{system_prompt: binary(), extra_messages: list()}`
  - Provider-specific translation hooks (e.g., `to_gemini_instruction/1`).
- Ensure provider adapters call the helper and respect returned instructions.
- Document the precedence in developer docs and CLI help.

## Testing
- Add test cases verifying precedence and provider-specific results (OpenAI vs Gemini).
- Include edge cases where multiple system messages are injected by workflows.

## Future Work
- Support localized/system prompts per intent or workflow tag.
- Provide UI to manage shared system prompts across teams/environments.
