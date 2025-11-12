# LLM Integration - Implementation Details
**Status**: ✅ Complete & Verified Live
**Date Completed**: October 29, 2025
**Providers**: Gemini, OpenAI

---

## Overview

Full multi-provider LLM integration with retry logic, telemetry, and live API verification.

### Verified Working (Oct 29, 2025)

```elixir
# Gemini Flash Lite - LIVE
{:ok, response} = Synapse.ReqLLM.chat_completion(
  %{prompt: "Review this code for security issues: ...", messages: []},
  profile: :gemini
)

# Response in ~300ms
response.content         # "The code exhibits SQL injection..."
response.metadata.total_tokens  # 981
response.metadata.provider      # :gemini
```

---

## Architecture

```
Request
  ↓
ReqLLM.chat_completion/2
  ↓
fetch_config() → resolve_profile() → resolve_model()
  ↓
build_request() (with retry config)
  ↓
Provider.prepare_body() (Gemini/OpenAI specific)
  ↓
Req.post() with exponential backoff
  ↓
Provider.parse_response()
  ↓
{:ok, %{content: "...", metadata: %{...}}}
```

---

## Components

### 1. ReqLLM Client (`lib/synapse/req_llm.ex`)

**Lines**: 650
**Purpose**: Multi-provider HTTP client with retry and telemetry

**Key Functions**:
```elixir
@spec chat_completion(map(), keyword()) :: {:ok, map()} | {:error, Error.t()}

# Example
ReqLLM.chat_completion(
  %{
    prompt: "User prompt",
    messages: [%{role: "user", content: "History"}],
    temperature: 0.7,
    max_tokens: 1000
  },
  profile: :gemini,
  model: "gemini-flash-lite-latest"
)
```

**Features**:
- Multi-profile configuration
- Model selection per request
- System prompt precedence (request > profile > global)
- Automatic retry with exponential backoff
- Telemetry events
- Token usage tracking
- Error translation per provider

---

### 2. Provider Adapters

#### Gemini Provider (`lib/synapse/providers/gemini.ex`)

**Lines**: 331
**Model**: `gemini-flash-lite-latest`
**Endpoint**: `/v1beta/models/{model}:generateContent`

**Gemini-Specific Behavior**:
- System prompts via `system_instruction` field (separate from messages)
- Role mapping: `assistant` → `model`, `user` → `user`
- Content format: `{"parts": [{"text": "..."}]}`
- Auth header: `x-goog-api-key` (not `authorization`)

**Example Payload**:
```json
{
  "contents": [
    {
      "role": "user",
      "parts": [{"text": "Say hello"}]
    }
  ],
  "system_instruction": {
    "parts": [{"text": "You are a helpful assistant"}]
  },
  "generationConfig": {
    "temperature": 0.7,
    "maxOutputTokens": 1000
  }
}
```

**Example Response**:
```json
{
  "candidates": [
    {
      "content": {
        "parts": [{"text": "Hello! How can I help you?"}],
        "role": "model"
      },
      "finishReason": "STOP"
    }
  ],
  "usageMetadata": {
    "promptTokenCount": 10,
    "candidatesTokenCount": 9,
    "totalTokenCount": 19
  }
}
```

---

#### OpenAI Provider (`lib/synapse/providers/openai.ex`)

**Model**: `gpt-4o-mini`, `gpt-4`, etc.
**Endpoint**: `/v1/chat/completions`

**OpenAI-Specific Behavior**:
- System prompts in messages array
- Role mapping: `assistant` remains `assistant`
- Standard OpenAI format
- Auth header: `authorization: Bearer {key}`

---

### 3. Configuration System

#### Options Schema (`lib/synapse/req_llm/options.ex`)

**Lines**: 283
**Purpose**: NimbleOptions validation for configs

**Profile Schema**:
```elixir
[
  base_url: [type: :string, required: true],
  api_key: [type: :string, required: true],
  model: [type: :string],
  endpoint: [type: :string, default: "/v1/chat/completions"],
  payload_format: [type: :atom],
  provider_module: [type: :atom],
  temperature: [type: {:or, [:float, :integer]}],
  max_tokens: [type: :pos_integer],
  retry: [type: :keyword_list, keys: retry_schema()],
  req_options: [type: :keyword_list]
]
```

---

#### System Prompt Management (`lib/synapse/req_llm/system_prompt.ex`)

**Precedence** (highest to lowest):
1. Request-level system messages
2. Profile-level system prompt
3. Global-level system prompt
4. Default: "You are a helpful assistant."

**Functions**:
```elixir
# Resolve base prompt
SystemPrompt.resolve(profile_config, global_config)

# Extract system messages from request
SystemPrompt.extract_system_messages(messages)

# Merge base + request-level
SystemPrompt.merge(base_prompt, request_system_messages)
```

---

### 4. Jido Action Wrapper

#### GenerateCritique (`lib/synapse/actions/generate_critique.ex`)

**Lines**: 126
**Purpose**: LLM action for agent workflows

**Schema**:
```elixir
schema: [
  prompt: [type: :string, required: true],
  messages: [type: {:list, :map}, default: []],
  temperature: [type: {:or, [:float, nil]}, default: nil],
  max_tokens: [type: {:or, [:integer, nil]}, default: nil],
  profile: [type: {:or, [:atom, :string]}, default: nil]
]
```

**Compensation**: Enabled with max 2 retries

**Usage in Agents**:
```elixir
{:ok, critique} = Jido.Exec.run(
  Synapse.Actions.GenerateCritique,
  %{
    prompt: "Analyze this code for vulnerabilities: #{diff}",
    profile: :gemini
  }
)

# Use critique.content in findings
```

---

## Configuration

### Runtime Config (`config/runtime.exs`)

```elixir
config :synapse, Synapse.ReqLLM,
  default_profile: :gemini,
  profiles: %{
    gemini: [
      base_url: "https://generativelanguage.googleapis.com",
      api_key: System.get_env("GEMINI_API_KEY"),
      model: "gemini-flash-lite-latest",
      endpoint: "/v1beta/models/{model}:generateContent",
      payload_format: :google_generate_content,
      auth_header: "x-goog-api-key",
      auth_header_prefix: nil,
      req_options: [receive_timeout: 30_000]
    ],
    openai: [
      base_url: "https://api.openai.com",
      api_key: System.get_env("OPENAI_API_KEY"),
      model: "gpt-5-nano",
      temperature: 1.0,
      req_options: [receive_timeout: 600_000]
    ]
  }
```

---

## Retry Logic

### Configuration
```elixir
retry: [
  max_attempts: 3,           # Total attempts
  base_backoff_ms: 300,      # Initial backoff
  max_backoff_ms: 5_000,     # Max backoff
  enabled: true
]
```

### Backoff Calculation
```elixir
# Exponential with jitter
delay = base * (2^attempt) + random_jitter
delay = min(delay, max_backoff)
```

### Retry Triggers
- HTTP 408 (Timeout)
- HTTP 429 (Rate Limited)
- HTTP 5xx (Server Errors)

---

## Telemetry

### Events

```elixir
# Request started
[:synapse, :llm, :request, :start]
%{system_time: integer}
%{request_id: string, profile: atom, model: string, provider: atom}

# Request completed
[:synapse, :llm, :request, :stop]
%{duration: integer}
%{request_id: string, profile: atom, model: string, provider: atom,
  token_usage: %{total: int}, finish_reason: string}

# Request failed
[:synapse, :llm, :request, :exception]
%{duration: integer}
%{request_id: string, profile: atom, error_type: atom, error_message: string}
```

### Example Handler
```elixir
:telemetry.attach(
  "llm-metrics",
  [:synapse, :llm, :request, :stop],
  fn _name, measurements, metadata, _config ->
    Logger.info("LLM request",
      duration_ms: measurements.duration,
      tokens: metadata.token_usage.total_tokens,
      provider: metadata.provider
    )
  end,
  nil
)
```

---

## Performance

### Gemini Flash Lite
- **Model**: `gemini-flash-lite-latest`
- **Latency**: 200-500ms typical
- **Tokens**: ~1000 for complex analysis
- **Cost**: Very low (free tier available)

### OpenAI
- **Model**: `gpt-4o-mini`
- **Latency**: 500-2000ms typical
- **Tokens**: Variable
- **Cost**: Per token pricing

---

## Error Handling

### Provider-Specific Translation

#### Gemini Errors
```elixir
# 404 - Model not found
"models/gemini-1.5-flash is not found for API version v1beta"

# 403 - Auth failure
"Method doesn't allow unregistered callers"

# No candidates - Content filtered
"Gemini response contained no candidates (content may have been blocked)"
```

#### OpenAI Errors
```elixir
# 401 - Invalid key
"Incorrect API key provided"

# 429 - Rate limit
"Rate limit exceeded"

# 500 - Server error
"OpenAI API returned server error"
```

---

## Testing

### Test Coverage

**Total**: 14 LLM tests, all passing

**Categories**:
- Profile switching (Gemini ↔ OpenAI)
- Configuration validation
- Error handling (401, 500, timeout)
- Retry logic
- System prompt precedence
- Token mapping (`max_tokens` → `max_completion_tokens`)

### Mocking with Req.Test

```elixir
setup do
  stub = :test_stub

  Req.Test.expect(stub, fn conn ->
    Req.Test.json(conn, %{
      "candidates" => [
        %{"content" => %{"parts" => [%{"text" => "Response"}]}}
      ]
    })
  end)

  config = [
    profiles: %{
      gemini: [
        base_url: "https://test",
        api_key: "test-key",
        plug: {Req.Test, stub},
        plug_owner: self()
      ]
    }
  ]

  Application.put_env(:synapse, Synapse.ReqLLM, config)
end
```

---

## Usage Examples

### Basic Request
```elixir
{:ok, response} = Synapse.ReqLLM.chat_completion(
  %{prompt: "Say hello", messages: []},
  profile: :gemini
)

IO.puts(response.content)
```

### With Conversation History
```elixir
{:ok, response} = Synapse.ReqLLM.chat_completion(
  %{
    prompt: "What's next?",
    messages: [
      %{role: "user", content: "What is Elixir?"},
      %{role: "assistant", content: "Elixir is a functional language..."}
    ]
  },
  profile: :gemini
)
```

### Override Model & Temperature
```elixir
{:ok, response} = Synapse.ReqLLM.chat_completion(
  %{prompt: "Code review", messages: []},
  profile: :gemini,
  model: "gemini-1.5-pro-latest",
  temperature: 0.3
)
```

---

## Known Issues & Limitations

### Current Limitations
- **No streaming support** - Full response only
- **No token budgeting** - No cost tracking yet
- **No caching** - Every request hits API
- **Single timeout** - No separate connect/read timeouts

### Planned Improvements (Stage 3+)
- Streaming response support
- Token budget tracking
- Response caching (semantic cache)
- Circuit breakers for cascading failures
- Fallback providers (Gemini → OpenAI)

---

## Migration Notes

### From Old Config Format
Old configs are automatically migrated:
```elixir
# Old (single profile)
config :synapse, Synapse.ReqLLM,
  base_url: "...",
  api_key: "..."

# Automatically becomes:
config :synapse, Synapse.ReqLLM,
  default_profile: :default,
  profiles: %{
    default: [base_url: "...", api_key: "..."]
  }
```

---

## Troubleshooting

### "Model not found" Error
**Cause**: Invalid model name for provider
**Fix**: Check available models for your provider

### Timeout Errors
**Cause**: LLM taking too long
**Fix**: Increase `receive_timeout` in `req_options`

### "Configuration missing" Error
**Cause**: No API key set
**Fix**: `export GEMINI_API_KEY="your-key"`

### Identical Responses
**Cause**: Might be using test mocks
**Fix**: Check for `:plug` field in config (should be nil in production)

---

**Implementation Date**: October 2025
**Verified Live**: October 29, 2025
**Status**: Production Ready ✅
