# Synapse LLM Integration – Continuation Prompt

This document aggregates the key context, configuration, and outstanding issues needed to resume debugging the `mix synapse.demo` workflow that calls external LLM providers via `Synapse.ReqLLM`.

---

## 1. Runtime Configuration

- Runtime config lives in `config/runtime.exs`.
- Profiles are assembled from environment variables:

  ```elixir
  openai_key = System.get_env("OPENAI_API_KEY")
  gemini_key = System.get_env("GEMINI_API_KEY")

  profiles = %{}
  profiles =
    if openai_key do
      Map.put(profiles, :openai,
        base_url: "https://api.openai.com",
        api_key: openai_key,
        model: "gpt-5-nano",
        allowed_models: ["gpt-5-nano"],
        temperature: 1.0
      )
    else
      profiles
    end

  profiles =
    if gemini_key do
      Map.put(profiles, :gemini,
        base_url: "https://generativelanguage.googleapis.com",
        api_key: gemini_key,
        model: "gemini-flash-lite-latest",
        allowed_models: ["gemini-flash-lite-latest"],
        endpoint: "/v1beta/models/{model}:generateContent",
        temperature: nil
      )
    else
      profiles
    end

  if map_size(profiles) > 0 do
    default_profile = if Map.has_key?(profiles, :openai), do: :openai, else: Map.keys(profiles) |> hd()

    config :synapse, Synapse.ReqLLM,
      default_profile: default_profile,
      profiles: profiles
  end
  ```

- Without `OPENAI_API_KEY` or `GEMINI_API_KEY`, no profiles are registered and every LLM call will fail with `"Synapse.ReqLLM configuration is missing"`.

**Action items**:
1. Ensure env variables are exported in the shell **before** running `mix synapse.demo`.
2. Consider adding a guard in `mix task` or `Synapse.ReqLLM` to raise a friendly error if no profiles exist (currently it attempts the call and hangs/fails).

---

## 2. Synapse.ReqLLM Overview (`lib/synapse/req_llm.ex`)

Key capabilities:
- Supports multiple profiles with per-model allow lists (`allowed_models`), custom endpoints, optional default `temperature`/`max_tokens`.
- Translates per-call options (`profile`, `model`, `temperature`, `max_tokens`) and merges with profile defaults.
- Uses Req for HTTP requests; in tests we pass `plug: {Req.Test, stub}` and `plug_owner: self()` to stub responses.
- If `profile` is unset, defaults to `default_profile` (OpenAI if key present).
- Ensures models are in `allowed_models`; otherwise returns `config_error`.
- `temperature` handling respects provider defaults: if the caller omits it and profile sets one (e.g., OpenAI -> 1.0), the request inherits that value.

Potential follow-ups:
- Add explicit check in `fetch_config/0` to raise when no profiles exist.
- Add connection/response timeout tuning and better logging when HTTP requests hang or fail.
- Extend Gemini payload formatting (`/generateContent` expects `contents` rather than OpenAI style `messages`).

---

## 3. GenerateCritique Action (`lib/synapse/actions/generate_critique.ex`)

```elixir
use Jido.Action,
  name: "generate_critique",
  schema: [
    prompt: [type: :string, required: true],
    messages: [type: {:list, :map}, default: []],
    temperature: [type: {:or, [:float, :nil]}, default: nil],
    max_tokens: [type: {:or, [:integer, :nil]}, default: nil],
    profile: [type: {:or, [:atom, :string]}, default: nil]
  ]

def run(params, _context) do
  llm_params = Map.take(params, [:prompt, :messages, :temperature, :max_tokens])
  profile = Map.get(params, :profile)
  ReqLLM.chat_completion(llm_params, profile: profile)
end
```

- Any validation errors (e.g., temperature not allowed) return a `%Jido.Error{}`.
- For CLI or workflow calls, ensure `profile` matches one configured profile (`:openai`, `"openai"`, etc.).

---

## 4. CLI Task (`lib/mix/tasks/synapse.demo.ex`)

Usage:
```
mix synapse.demo --message "..." --intent "..." [--provider openai|gemini] [--constraint ...]
```

Flow:
1. Starts app (loads runtime config).
2. Runs `ReviewOrchestrator.evaluate/1`.
3. Prints suggestion and metadata.

Important: if no profiles exist, the task eventually fails when `GenerateCritique` executes; consider adding a guard after `Mix.Task.run("app.start")`:

```elixir
unless Application.get_env(:synapse, Synapse.ReqLLM) do
  Mix.raise("No LLM profiles configured; set OPENAI_API_KEY or GEMINI_API_KEY.")
end
```

---

## 5. ReviewOrchestrator Flow (`lib/synapse/workflows/review_orchestrator.ex`)

- Accepts `%{message, intent, constraints?, llm_profile?}` map.
- Runs:
  1. `SimpleExecutor.cmd/2` – echo action to simulate generation.
  2. `CriticAgent.cmd/2` – critic review and state tracking.
  3. `GenerateCritique` – LLM suggestion via `llm_profile` (if provided).
- Returns `%{executor_output, review, suggestion, audit_trail}` or `{:error, reason}`.

For debugging:
- Add logging/IO in `request_llm_suggestion/3` to confirm profile selection.
- Verify `llm_profile` is atom/string matching the configured profile key.

---

## 6. Tests as References

- `test/synapse/actions/req_llm_action_test.exs`: demonstrates per-profile stubbing, model assertions, error handling.
- `test/synapse/workflows/review_orchestrator_test.exs`: verifies orchestrator with Gemini profile stub.
- `test/mix/tasks/synapse_demo_test.exs`: CLI flow using Req.Test stub to avoid network calls.

Use these tests as templates for reproducing issues by swapping Req.Test for real config.

---

## 7. Outstanding Issues / Next Steps

1. **Env Guarding** – add a friendly error when no profiles exist (prevents hanging network call).
2. **Gemini Payload** – current request body mirrors OpenAI format; adjust to Gemini’s expected schema (likely `contents` field).
3. **Retry Strategy** – consider configurable retries/backoff beyond the default single attempt.
4. **CLI UX** – optionally add `--profile` alias/validation and surface which profile was used.

---

## 8. Helpful Commands

```bash
# Export API keys (set actual secrets before running)
export OPENAI_API_KEY=sk-...
export GEMINI_API_KEY=AIza...

# Run CLI workflow (default OpenAI)
mix synapse.demo --message "def foo, do: :ok" --intent "Define a function"

# Force Gemini profile
mix synapse.demo --message "..." --intent "..." --provider gemini

# Run targeted test
mix test test/synapse/actions/req_llm_action_test.exs --seed 0
```

Keep this file up to date with further findings or configuration tweaks so the next debugging session can resume quickly.***
