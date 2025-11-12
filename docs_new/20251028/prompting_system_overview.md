# Synapse Prompting System Overview

## Architecture

Your prompting system has a **multi-layered** approach with clear precedence rules and provider-specific handling.

---

## Entry Points

### 1. High-Level Action: `Synapse.Actions.GenerateCritique`

**Purpose:** Jido action wrapper for LLM requests
**Location:** `lib/synapse/actions/generate_critique.ex`

**API:**
```elixir
Jido.Exec.run(
  GenerateCritique,
  %{
    prompt: "Your question here",              # Required: main user prompt
    messages: [                                 # Optional: conversation history
      %{role: "system", content: "Custom system prompt"},
      %{role: "user", content: "Previous message"}
    ],
    temperature: 0.7,                          # Optional: sampling temperature
    max_tokens: 500,                           # Optional: token limit
    profile: :openai                           # Optional: which LLM provider
  }
)
```

**Delegates to:** `Synapse.ReqLLM.chat_completion/2`

---

### 2. Core Engine: `Synapse.ReqLLM.chat_completion/2`

**Purpose:** HTTP client for multi-provider LLM requests
**Location:** `lib/synapse/req_llm.ex:68`

**API:**
```elixir
ReqLLM.chat_completion(
  %{
    prompt: "Your question",                   # OR use :messages for full control
    messages: [...],                           # Optional: message list
    temperature: 0.8,                          # Optional: per-request override
    max_tokens: 200                            # Optional: per-request override
  },
  profile: :openai,                            # Optional: profile selection
  timeout: 30_000                              # Optional: timeout override
)
```

---

## System Prompt Precedence

Your system implements a **3-tier precedence hierarchy**:

### Tier 1: Request-Level System Messages (Highest Priority)
```elixir
ReqLLM.chat_completion(
  %{
    prompt: "Write a function",
    messages: [
      %{role: "system", content: "You are a Rust expert"}  # ← Wins!
    ]
  }
)
```

**How it works:**
- If `params.messages` contains `role: "system"`, those are included
- **OpenAI:** System messages prepended to conversation
- **Gemini:** System messages merged into `system_instruction` field

---

### Tier 2: Profile-Level System Prompt (Medium Priority)
```elixir
# config/runtime.exs
profiles: %{
  openai: [
    base_url: "https://api.openai.com",
    api_key: "...",
    system_prompt: "You are a meticulous code reviewer"  # ← Profile default
  ]
}
```

**When used:** If no system messages in request, uses profile's `system_prompt`

---

### Tier 3: Global Fallback (Lowest Priority)
```elixir
# config/runtime.exs
config :synapse, Synapse.ReqLLM,
  system_prompt: "You are a helpful assistant",  # ← Global fallback
  profiles: %{...}
```

**When used:** If no profile-level or request-level system prompt exists

---

### Tier 4: Provider Hardcoded Default (Last Resort)
```elixir
# lib/synapse/providers/openai.ex:181
"You are a helpful assistant."  # ← If nothing else specified
```

---

## Provider-Specific Handling

### OpenAI (`Synapse.Providers.OpenAI`)

**Message Structure:**
```elixir
# Final payload sent to OpenAI
{
  "model": "gpt-4o-mini",
  "messages": [
    {"role": "system", "content": "<resolved system prompt>"},
    {"role": "user", "content": "Previous message"},
    {"role": "assistant", "content": "Previous response"},
    {"role": "user", "content": "<your prompt>"}
  ]
}
```

**Key behaviors:**
- System prompt always goes **first** in messages array
- Accepts multiple system messages (all preserved)
- Standard OpenAI chat format

---

### Gemini (`Synapse.Providers.Gemini`)

**Message Structure:**
```elixir
# Final payload sent to Gemini
{
  "system_instruction": {
    "parts": [{"text": "<merged system prompts>"}]
  },
  "contents": [
    {"role": "user", "parts": [{"text": "Previous message"}]},
    {"role": "model", "parts": [{"text": "Previous response"}]},
    {"role": "user", "parts": [{"text": "<your prompt>"}]}
  ]
}
```

**Key behaviors:**
- System prompts extracted from messages and merged into `system_instruction`
- Multiple system messages **joined with `\n\n`** separator
- Role mapping: `"assistant"` → `"model"`, `"user"` → `"user"`
- System messages never appear in `contents` array

**Code:** `lib/synapse/providers/gemini.ex:48-76`

---

## Message Formats Accepted

Your system accepts **two input formats**:

### Format 1: Simple Prompt (Most Common)
```elixir
%{
  prompt: "Write a sorting algorithm",
  messages: []
}
```

**Converted to:** `[{"role": "user", "content": "Write a sorting algorithm"}]`

---

### Format 2: Full Message List (Advanced)
```elixir
%{
  messages: [
    %{role: "system", content: "You are an expert"},
    %{role: "user", content: "First question"},
    %{role: "assistant", content: "First response"},
    %{role: "user", content: "Follow-up question"}
  ]
}
```

**No conversion needed** - messages used directly

---

### Format 3: Hybrid (Both)
```elixir
%{
  prompt: "Follow-up question",
  messages: [
    %{role: "system", content: "You are an expert"},
    %{role: "user", content: "First question"},
    %{role: "assistant", content: "First response"}
  ]
}
```

**Result:** `prompt` is appended as final user message

---

## Real-World Usage Example

From `lib/synapse/workflows/review_orchestrator.ex:46-72`:

```elixir
defp request_llm_suggestion(message, reviewer_feedback, profile) do
  feedback_json = Jason.encode!(reviewer_feedback)

  prompt = """
  Provide concrete next steps to strengthen the submission.

  Code:
  #{message}

  Critic feedback:
  #{feedback_json}
  """

  Jido.Exec.run(
    GenerateCritique,
    %{
      prompt: prompt,                          # ← Main prompt (goes to user message)
      messages: [                              # ← System instruction
        %{
          role: "system",
          content: "You are assisting a software engineer with rapid iteration."
        }
      ],
      profile: profile                         # ← Provider selection
    }
  )
end
```

**Result sent to LLM:**
1. **System message:** "You are assisting a software engineer..."
2. **User message:** "Provide concrete next steps... [code] [feedback]"

---

## Parameter Resolution Flow

```
Request Parameters
    ↓
+-------------------+
| GenerateCritique  |  ← Jido Action wrapper
|  (validates args) |
+-------------------+
    ↓
+-------------------+
| ReqLLM            |  ← Coordinator
|  - Loads config   |
|  - Resolves model |
|  - Selects provider|
+-------------------+
    ↓
+-------------------+
| Provider Module   |  ← OpenAI/Gemini specific
|  - Merges system  |
|    prompt layers  |
|  - Formats payload|
|  - Handles roles  |
+-------------------+
    ↓
  HTTP Request
```

---

## System Prompt Resolution Logic

### In OpenAI Provider (`lib/synapse/providers/openai.ex:178-182`)

```elixir
defp resolve_system_prompt(profile_config, global_config) do
  Keyword.get(profile_config, :system_prompt) ||      # 1. Profile level
    Map.get(global_config, :system_prompt) ||         # 2. Global level
    "You are a helpful assistant."                    # 3. Default
end
```

**Then:**
- Resolved system prompt goes to first system message
- Any additional system messages from `params.messages` are preserved

---

### In Gemini Provider (`lib/synapse/providers/gemini.ex:41, 62-69`)

```elixir
# 1. Resolve base system prompt (same as OpenAI)
system_prompt = resolve_system_prompt(profile_config, global_config)

# 2. Extract system messages from incoming messages
{system_messages, dialog_messages} =
  Enum.split_with(normalized_messages, fn %{"role" => role} -> role == "system" end)

# 3. Merge all system prompts with deduplication
system_instruction_text =
  [system_prompt | Enum.map(system_messages, &Map.get(&1, "content"))]
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.uniq()                               # Remove duplicates
  |> Enum.join("\n\n")                         # Join with double newline
```

**Special Gemini handling:**
- All system content merged into single `system_instruction` field
- Duplicates removed automatically
- Multi-paragraph formatting with `\n\n` separator

---

## Key Design Decisions

### 1. Dual Input Modes
- **Simple:** `%{prompt: "..."}` for quick requests
- **Advanced:** `%{messages: [...]}` for multi-turn conversations
- **Hybrid:** Both together - prompt appended to messages

### 2. Provider Abstraction
- Each provider handles system prompts according to its API
- OpenAI: First message in array
- Gemini: Separate `system_instruction` field with merging

### 3. Precedence is Clear
Profile system prompt → Global system prompt → Default → (all can be overridden by request-level system messages)

### 4. No Message Mutation at Top Level
- `GenerateCritique` action doesn't modify messages
- All prompt construction happens in provider modules
- Maintains clean separation of concerns

---

## Current Gaps (from Critique #9)

From `docs/20251028/01_critique_llm_arch.md:166-176`:

> **Problem:** System prompt resolution is scattered
> - Can be set at global, profile, or message level
> - Resolution logic spans multiple functions
> - Gemini merges differently than OpenAI

**Status:** Partially addressed
- ✅ Providers now own their system prompt logic
- ✅ Precedence is consistent (profile > global > default)
- ⚠️ Documentation could be clearer (not in main README)
- ⚠️ No explicit test validating precedence order

---

## Recommendations for Clarity

### 1. Document Precedence Explicitly
Add to main module docs:

```elixir
## System Prompt Precedence

System prompts are resolved in this order (highest to lowest):

1. System messages in params.messages
2. Profile-level :system_prompt
3. Global :system_prompt
4. Provider default ("You are a helpful assistant")
```

### 2. Add Precedence Test
```elixir
test "system prompt precedence: request > profile > global" do
  # Test that request-level system messages override profile config
end
```

### 3. Helper Function (Optional)
```elixir
# Could add to ReqLLM public API
def explain_system_prompt(profile_name) do
  # Returns which system prompt would be used and why
end
```

---

## Summary

**Your Prompting System:**
- ✅ Flexible (simple or advanced API)
- ✅ Multi-provider support (OpenAI, Gemini)
- ✅ Clear precedence hierarchy
- ✅ Provider-specific optimizations
- ✅ Conversation history support
- ⚠️ Could use better documentation
- ⚠️ Precedence not explicitly tested

**Overall:** Well-designed system with good separation of concerns. Main improvement would be better documentation of the precedence rules.
