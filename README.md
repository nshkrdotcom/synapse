<p align="center">
  <img src="assets/synapse.svg" alt="Synapse Logo" width="150"/>
</p>

# Synapse

[![Hex.pm](https://img.shields.io/hexpm/v/synapse.svg)](https://hex.pm/packages/synapse)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs.pm-blue.svg)](https://hexdocs.pm/synapse)
[![Downloads](https://img.shields.io/hexpm/dt/synapse.svg)](https://hex.pm/packages/synapse)
[![Elixir](https://img.shields.io/badge/elixir-~%3E%201.15-purple.svg)](https://elixir-lang.org/)
[![License](https://img.shields.io/hexpm/l/synapse.svg)](LICENSE)

Version: v0.1.1 (2025-11-29)

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

## Custom Signal Domains

Synapse supports custom signal domains beyond code review. Define your own signals in config:

```elixir
# config/config.exs
config :synapse, Synapse.Signal.Registry,
  topics: [
    ticket_created: [
      type: "support.ticket.created",
      schema: [
        ticket_id: [type: :string, required: true],
        customer_id: [type: :string, required: true],
        subject: [type: :string, required: true],
        priority: [type: {:in, [:low, :medium, :high]}, default: :medium]
      ]
    ]
  ]
```

Or register at runtime:

```elixir
Synapse.Signal.register_topic(:my_event,
  type: "my.domain.event",
  schema: [id: [type: :string, required: true]]
)
```

## Agent Configuration

Orchestrator agents can specify signal roles for custom domains:

```elixir
%{
  id: :my_coordinator,
  type: :orchestrator,
  signals: %{
    subscribes: [:ticket_created, :ticket_analyzed],
    emits: [:ticket_resolved],
    roles: %{
      request: :ticket_created,
      result: :ticket_analyzed,
      summary: :ticket_resolved
    }
  },
  orchestration: %{
    classify_fn: &MyApp.classify/1,
    spawn_specialists: [:analyzer, :responder],
    aggregation_fn: &MyApp.aggregate/2
  }
}
```

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

## Declarative Workflow Engine

The workflow engine executes declarative specs (steps + dependencies) with retries, compensation, and telemetry. It powers specialist runs and the coordinator paths while giving you a uniform audit trail and optional Postgres persistence.

Key pieces

- Spec: `Synapse.Workflow.Spec` with `Step` and `Output` helpers
- Engine: `Synapse.Workflow.Engine.execute/2` runs the spec and emits telemetry
- Persistence (optional): snapshots to `workflow_executions` via `Synapse.Workflow.Persistence`

Minimal example

```elixir
alias Synapse.Workflow.{Spec, Engine}
alias Synapse.Workflow.Spec.Step

spec =
  Spec.new(
    name: :example_workflow,
    description: "Analyze and generate critique with retries",
    metadata: %{version: 1},
    steps: [
      Step.new(
        id: :fetch_context,
        action: MyApp.Actions.FetchContext,
        # env = %{input, results, context, step, workflow}
        params: fn env -> %{id: env.input.review_id} end
      ),
      Step.new(
        id: :analyze,
        action: Synapse.Actions.CriticReview,
        requires: [:fetch_context],
        retry: [max_attempts: 3, backoff: 200],
        on_error: :continue,
        params: fn env -> %{diff: env.input.diff, metadata: env.results.fetch_context} end
      ),
      Step.new(
        id: :generate_critique,
        action: Synapse.Actions.GenerateCritique,
        requires: [:analyze],
        params: fn env ->
          review = env.results.analyze
          %{
            prompt: "Summarize issues",
            messages: [%{role: "user", content: Enum.join(review.issues || [], ", ")}],
            profile: :openai
          }
        end
      )
    ],
    outputs: [
      Spec.output(:review, from: :analyze),
      Spec.output(:critique, from: :generate_critique, path: [:content])
    ]
  )

input = %{review_id: "PR-42", diff: "..."}
ctx = %{request_id: "req_abc123"} # required when persistence is enabled

case Engine.execute(spec, input: input, context: ctx) do
  {:ok, %{results: _results, outputs: outputs, audit_trail: audit}} ->
    IO.inspect(outputs.critique, label: "Critique")
    IO.inspect(audit.steps, label: "Audit trail")

  {:error, %{failed_step: step, error: error, audit_trail: audit}} ->
    IO.inspect({step, error}, label: "Workflow failed")
    IO.inspect(audit.steps, label: "Audit trail")
end
```

Parameters and env

- Step params may be a map/keyword, or a function `fn env -> ... end` where `env` includes `:input`, `:results`, `:context`, `:step`, and `:workflow`.
- Steps support `requires: [:other_step]`, `retry: [max_attempts:, backoff:]`, and `on_error: :halt | :continue`.
- Outputs map step results to the final payload; `path` lets you pick nested fields; `transform` is available for custom shaping.

Persistence

- Dev config enables persistence by default: see `config/config.exs` for `config :synapse, Synapse.Workflow.Engine, persistence: {Synapse.Workflow.Persistence.Postgres, []}`.
- When persistence is enabled, you must provide a `:request_id` in `context`; the engine will snapshot before/after steps to `workflow_executions`.
- You can override per call: `Engine.execute(spec, input: ..., context: ..., persistence: nil)`.

Telemetry

- Emits `[:synapse, :workflow, :step, :start|:stop|:exception]` with metadata like `:workflow`, `:workflow_step`, `:workflow_attempt`.
- Example handler:

```elixir
:telemetry.attach(
  "wf-logger",
  [[:synapse, :workflow, :step, :stop]],
  fn _evt, m, meta, _ ->
    require Logger
    Logger.info("step done",
      workflow: meta.workflow,
      step: meta.workflow_step,
      attempt: meta.workflow_attempt,
      duration_us: m.duration_us
    )
  end,
  nil
)
```

Error and result shapes

- Success: `{:ok, %{results: map(), outputs: map(), audit_trail: map()}}`
- Failure: `{:error, %{failed_step: atom(), error: term(), attempts: pos_integer(), results: map(), audit_trail: map()}}`

Further reading

- Cookbook: `docs_new/workflows/engine.md`
- ADR: `docs_new/adr/0004-declarative-workflow-engine.md`

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
