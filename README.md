<p align="center">
  <img src="assets/synapse.svg" alt="Synapse Logo" width="150"/>
</p>

# Synapse

[![Hex.pm](https://img.shields.io/hexpm/v/synapse.svg)](https://hex.pm/packages/synapse)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs.pm-blue.svg)](https://hexdocs.pm/synapse)
[![Downloads](https://img.shields.io/hexpm/dt/synapse.svg)](https://hex.pm/packages/synapse)
[![Elixir](https://img.shields.io/badge/elixir-~%3E%201.15-purple.svg)](https://elixir-lang.org/)
[![License](https://img.shields.io/hexpm/l/synapse.svg)](LICENSE)

Version: v0.1.0 (2025-11-11)

Synapse is a headless, declarative multi‑agent runtime for code review orchestration. It exposes a signal bus API (`Synapse.SignalRouter`) and a workflow engine with Postgres persistence so you can submit review work, fan it out to specialists, negotiate conflicts, and consume structured summaries — all without a Phoenix UI.

Highlights

- Declarative orchestrator runtime (no GenServer boilerplate)
- Signal bus with typed topics and contract enforcement
- Specialist agents defined via actions + `state_schema`
- Workflow engine with persistence and audit trail (`workflow_executions`)
- LLM gateway powered by `Req` with OpenAI and Gemini providers
- Telemetry throughout (router, workflows, LLM requests)

## Quick Start

1. **Install dependencies**

   ```bash
   mix setup
   ```

2. **Create and migrate the database**

   By default, dev connects to `postgres://postgres:postgres@localhost:5432/synapse_dev`. Override via `POSTGRES_*` env vars (see config/dev.exs).

   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

3. **Run the Stage 2 demo (optional sanity check)**

   ```bash
   mix run examples/stage2_demo.exs
   ```

   This boots the runtime, publishes a review request, and prints the resulting summary so you can see the declarative orchestrator in action.

4. **Start the runtime for development**

   ```bash
   iex -S mix
   ```

   This boots `Synapse.Runtime`, the signal router, the orchestrator runtime (reading `priv/orchestrator_agents.exs`), and the workflow engine with Postgres persistence. The application is OTP‑only — no Phoenix endpoint is required.

## Submit a Review Request

Publish a `:review_request` signal from CI, a script, or an iex session:

```elixir
{:ok, _signal} =
  Synapse.SignalRouter.publish(
    Synapse.SignalRouter,
    :review_request,
    %{
      review_id: "PR-12345",
      diff: git_diff,
      files_changed: 12,
      labels: ["security"],
      intent: "feature",
      metadata: %{repo: "org/app", author: "alice", files: touched_paths}
    },
    source: "/ci/github"
  )
```

The coordinator workflow classifies the request, spawns security/performance specialists as needed, and persists every step to `workflow_executions`.

## Consume Results

Subscribe to summaries if you want push-style notifications:

```elixir
{:ok, _sub_id} = Synapse.SignalRouter.subscribe(Synapse.SignalRouter, :review_summary)

receive do
  {:signal, %{type: "review.summary", data: summary}} ->
    IO.inspect(summary, label: "Review complete")
end
```

Or query Postgres for historical/auditable data:

```elixir
Synapse.Workflow.Execution
|> where(review_id: "PR-12345")
|> Synapse.Repo.one!()
```

Each execution record includes the workflow name, step-by-step audit trail, accumulated results, and the final status, so you can drive dashboards or rerun failed work.

## Orchestrator & Specialists

Specialists and the coordinator are declared in `priv/orchestrator_agents.exs` and are reconciled and run by `Synapse.Orchestrator.Runtime`. Update this file to add or tune agents — no GenServer code needed.

Example snippet:

```elixir
%{
  id: :coordinator,
  type: :orchestrator,
  actions: [Synapse.Actions.Review.ClassifyChange],
  orchestration: %{
    classify_fn: &MyStrategies.classify/1,
    spawn_specialists: [:security_specialist, :performance_specialist],
    aggregation_fn: &MyStrategies.aggregate/2,
    negotiate_fn: &MyStrategies.resolve_conflicts/2
  },
  signals: %{subscribes: [:review_request, :review_result], emits: [:review_summary]},
  state_schema: [review_count: [type: :non_neg_integer, default: 0]]
}
```

On boot, the orchestrator runtime validates configs, spawns any missing agents, and monitors process health. Update the file and trigger a reload to reconcile changes.

## LLM Providers (Req)

Synapse uses `Req` for HTTP and provides a multi‑provider LLM gateway. Configure at runtime via environment:

```bash
export OPENAI_API_KEY=sk-...
# or
export GEMINI_API_KEY=ya29....
```

Configuration is assembled in `config/runtime.exs`. Profiles support timeouts, retries, and provider‑specific options.

Example usage:

```elixir
{:ok, resp} =
  Synapse.ReqLLM.chat_completion(%{
    messages: [%{role: "user", content: "Summarize the following diff..."}],
    temperature: 0.2
  }, profile: :openai)

resp.content     # normalized string content
resp.metadata    # token usage, finish_reason, provider-specific details
```

See: `lib/synapse/req_llm.ex`, `lib/synapse/providers/*`, and `docs_new/20251029/implementation/LLM_INTEGRATION.md`.

## Persistence

- Adapter: `Synapse.Workflow.Persistence.Postgres`
- Schema: `workflow_executions` (created by migration at `priv/repo/migrations/*_create_workflow_executions.exs`)
- Test env disables persistence by default (`config/test.exs`)

Common tasks:

```bash
mix ecto.create
mix ecto.migrate
mix ecto.rollback
```

Database configuration for dev can be overridden with `POSTGRES_HOST`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_PORT`, `POSTGRES_POOL_SIZE`.

## Telemetry

- Signals: `[:synapse, :signal_router, :publish|:deliver]`
- LLM: `[:synapse, :llm, :request, :start|:stop|:exception]`
- Workflows/Orchestrator: see `docs_new/20251028/remediation/telemetry_documentation.md`

Attach your own handlers using `:telemetry.attach/4`.

## Tests

Run the full suite with:

```bash
mix test
```

Dialyzer and other pre-commit checks are available via `mix precommit`.

## Roadmap & Docs

- Roadmap: `ROADMAP.md`
- Orchestrator design and reference: `docs_new/20251028/synapse_orchestrator/README.md`
- Multi‑agent framework docs: `docs_new/20251028/multi_agent_framework/README.md`
- Workflow engine and persistence: `docs_new/workflows/engine.md` and ADRs in `docs_new/adr/`
- Post‑Phoenix direction: `docs_new/20251109/README.md`

## Changelog

See `CHANGELOG.md`.

## Tags

elixir • otp • jido • req • multi‑agent • orchestrator • workflows • llm • openai • gemini • postgres • telemetry

## License

Licensed under MIT. See [LICENSE](LICENSE).
