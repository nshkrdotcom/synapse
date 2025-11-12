# Error Sanitization & Privacy Controls

## Problem Statement
- Error metadata currently includes full response bodies, which may contain sensitive data (user prompts, credentials, internal messages).
- Logs or CLI output can inadvertently expose provider-specific details or secrets.
- No standardized mechanism exists to redact sensitive fields across providers.

## Goals
1. Sanitize error details before propagating to `Jido.Error`.
2. Provide configurable verbosity levels (e.g., “basic”, “debug”).
3. Ensure sensitive headers (API keys) are never logged.

## Proposed Solution
- Introduce `Synapse.ReqLLM.ErrorSanitizer` module responsible for:
  - Redacting known sensitive keys (`"api_key"`, `"Authorization"`, etc.).
  - Limiting body excerpts to a safe subset (e.g., top-level error message + code).
  - Attaching a reference ID for deep debugging when verbose logging is enabled.
- Provider adapters can supply provider-specific sanitizers to capture relevant error codes while still redacting content.

## Implementation Steps
1. Define sanitation rules and integrate into error translation pipeline.
2. Update CLI to render human-friendly error messages and reference IDs.
3. Add tests covering sanitized output for 401/429/500 errors.

## Future Enhancements
- Integrate with observability pipeline to store sanitized errors alongside telemetry.
- Provide developer-only debug mode (ENV flag) that includes raw responses for local troubleshooting.
