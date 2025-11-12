# Streaming Support for LLM Responses

## Problem Statement
- Current integration only supports full-response HTTP calls.
- Providers such as OpenAI and Gemini offer streaming interfaces (SSE or chunked JSON) for reduced latency and better UX.
- Without streaming, long generations block the UI and risk hitting timeouts.

## Goals
1. Add streaming support alongside existing non-streaming API.
2. Provide a consistent callback/consumer API for LiveView and CLI usage.
3. Handle partial messages, finish reasons, and clean shutdown of streams.

## Proposed Architecture
- Extend `Synapse.ReqLLM` with `chat_completion_stream(params, opts, handler)` returning `{:ok, ref}`.
- Provider modules expose streaming capability via callbacks (`stream_request/4`) leveraging Req’s streaming API (`response: :stream`).
- Handler receives events: `{:chunk, text}`, `{:metadata, map}`, `{:done, final_state}`, `{:error, error}`.
- Support integration with Jido by introducing a streaming action variant or enabling streaming inside existing action via `Task`.

## Implementation Steps
1. Identify provider streaming endpoints and payload requirements.
2. Update provider modules to implement streaming callbacks; include fallback to non-streaming if not supported.
3. Add tests using `Req.Test` with chunked responses to validate handler behavior.
4. Document streaming API usage, including cleanup and telemetry events.

## Future Considerations
- Provide LiveView helpers for progressive rendering.
- Allow recording of streamed content for audit/a11y purposes.
- Integrate with retry/circuit breaker logic (e.g., restart stream on transient errors).
