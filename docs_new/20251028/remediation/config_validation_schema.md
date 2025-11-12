# Configuration Validation & Schema Enforcement

## Problem Statement
- `Synapse.ReqLLM` manually maps string keys to atoms and raises runtime errors for unknown keys.
- Valid configuration keys are not documented and runtime failures are difficult to debug.
- Mixed key types (strings vs atoms) introduce subtle bugs and complicate validation.

## Goals
1. Provide declarative schemas for profile and global configuration.
2. Fail fast with descriptive errors during boot or compilation.
3. Generate documentation (CLI help, docs) from the schema definitions.

## Proposed Approach
- Adopt `NimbleOptions` to define configuration schemas for:
  - Global options (`default_profile`, `system_prompt`, etc.).
  - Profile-level options (base URL, model, provider module, timeouts).
- Optionally expose schema metadata via `mix help` or a custom `mix synapse.llm.config` task.

## Implementation Plan
1. Create a module `Synapse.ReqLLM.Options` encapsulating NimbleOptions definitions.
2. Update runtime config loader to call `NimbleOptions.validate!/2` and store the normalized keyword list.
3. Provide helper functions to convert validated options into Req configuration structs.
4. Add documentation that enumerates all supported keys and their types/defaults.

## Future Considerations
- Generate JSON schema for tooling (IDE hints, config editors).
- Support environment-variable interpolation or secrets management integration.
