# Synapse Ecosystem Architecture

A competitive multi-agent and workflow framework ecosystem for Elixir/OTP.

## Ecosystem Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER APPLICATIONS                                  │
│  (Your apps that compose the ecosystem)                                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌───────────────┐           ┌───────────────┐           ┌───────────────┐
│ Domain Packs  │           │  Connectors   │           │   Tooling     │
│               │           │               │           │               │
│ code_review   │           │ github        │           │ synapse_cli   │
│ support_desk  │           │ slack         │           │ synapse_ui    │
│ data_pipeline │           │ jira          │           │ synapse_test  │
│ doc_gen       │           │ linear        │           │ synapse_bench │
└───────┬───────┘           └───────┬───────┘           └───────┬───────┘
        │                           │                           │
        └───────────────────────────┼───────────────────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AGENT LAYER                                     │
│                                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ claude_sdk  │  │ codex_sdk   │  │ gemini_sdk  │  │ ollama_sdk  │        │
│  │ (Anthropic) │  │ (OpenAI)    │  │ (Google)    │  │ (Local)     │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐        │
│  │                    synapse_agent_core                            │        │
│  │  (Unified agent interface, capability negotiation, tool routing) │        │
│  └─────────────────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SYNAPSE CORE                                       │
│                                                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │Signal Router │ │Agent Runtime │ │Workflow Eng. │ │ Persistence  │       │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘       │
│                                                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │  Telemetry   │ │  LLM Gateway │ │ Skill Reg.   │ │ State Mgmt   │       │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FOUNDATION                                        │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐        │
│  │                           jido                                   │        │
│  │            (Actions, Signal Bus, Execution primitives)           │        │
│  └─────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │     OTP      │ │    Ecto      │ │   Telemetry  │ │     Req      │       │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Layer 1: Foundation

### jido (existing)
The action/signal primitive layer. Keep as-is.

```elixir
{:jido, "~> 1.0"}
```

---

## Layer 2: Synapse Core

### synapse (existing, refined)
Strip to pure infrastructure. No domains.

```elixir
# What stays in synapse core:
lib/synapse/
├── signal_router.ex          # Pub/sub infrastructure
├── signal/registry.ex        # Dynamic topic registration
├── orchestrator/
│   ├── runtime.ex            # Agent lifecycle management
│   ├── agent_config.ex       # Configuration validation
│   ├── agent_factory.ex      # Agent spawning
│   └── skill.ex              # Skill/action registry
├── workflow/
│   ├── engine.ex             # Declarative execution
│   ├── spec.ex               # Workflow DSL
│   └── persistence/          # Storage adapters
├── req_llm.ex                # Multi-provider LLM gateway
├── providers/                # OpenAI, Gemini, etc.
└── telemetry.ex              # Instrumentation
```

**Remove from synapse core:**
- `lib/synapse/domains/` → extract to domain packages
- `priv/orchestrator_agents.exs` → move to examples/docs

---

## Layer 3: Agent SDKs

### synapse_agent_core (NEW)
Unified interface for all LLM agent backends.

```elixir
defmodule Synapse.Agent do
  @callback query(prompt :: String.t(), opts :: keyword()) ::
    {:ok, response()} | {:error, term()}

  @callback stream(prompt :: String.t(), opts :: keyword()) ::
    Enumerable.t()

  @callback capabilities() :: [atom()]  # [:tool_use, :vision, :code_execution, ...]

  @callback negotiate_tools(requested :: [Tool.t()]) ::
    {:ok, [Tool.t()]} | {:partial, [Tool.t()], rejected :: [Tool.t()]}
end

# Unified tool definition
defmodule Synapse.Agent.Tool do
  defstruct [:name, :description, :parameters, :handler]

  defmacro deftool(name, opts) do
    # Generates tool compatible with all agent backends
  end
end

# Provider routing
defmodule Synapse.Agent.Router do
  def route(task, opts \\ []) do
    # Select best agent for task based on:
    # - Required capabilities
    # - Cost constraints
    # - Latency requirements
    # - Availability
  end
end
```

### claude_agent_sdk (existing, adapter)
Wrap to implement `Synapse.Agent` behaviour.

```elixir
defmodule ClaudeAgentSDK.SynapseAdapter do
  @behaviour Synapse.Agent

  def query(prompt, opts) do
    ClaudeAgentSDK.query(prompt, translate_opts(opts))
  end

  def capabilities, do: [:tool_use, :vision, :code_execution, :streaming]
end
```

### codex_sdk (existing, adapter)
Same pattern.

```elixir
defmodule CodexSDK.SynapseAdapter do
  @behaviour Synapse.Agent
  # ...
end
```

### synapse_ollama (NEW)
Local model support via Ollama.

```elixir
defmodule Synapse.Ollama do
  @behaviour Synapse.Agent

  # Runs models locally - no API costs
  # Good for: development, sensitive data, high-volume low-stakes tasks
end
```

### synapse_gemini (NEW - or extract from synapse)
Google Gemini as standalone SDK.

---

## Layer 4: Domain Packages

### synapse_code_review (extract from synapse)
First domain package - proves the pattern.

```elixir
defmodule Synapse.CodeReview do
  use Synapse.Domain

  signals do
    topic :review_request, schema: [...]
    topic :review_result, schema: [...]
    topic :review_summary, schema: [...]
  end

  agents do
    specialist :security, actions: [CheckSQLInjection, CheckXSS, CheckAuthIssues]
    specialist :performance, actions: [CheckComplexity, CheckMemoryUsage]
    orchestrator :coordinator, specialists: [:security, :performance]
  end

  actions do
    # All the code review actions
  end
end
```

### synapse_support (NEW)
Support ticket triage and resolution.

```elixir
defmodule Synapse.Support do
  use Synapse.Domain

  signals do
    topic :ticket_created
    topic :ticket_classified
    topic :ticket_resolved
    topic :escalation_needed
  end

  agents do
    specialist :classifier, actions: [ClassifyTicket, ExtractEntities]
    specialist :resolver, actions: [SearchKnowledgeBase, DraftResponse]
    specialist :escalator, actions: [NotifyHuman, CreateJiraIssue]
    orchestrator :triage, specialists: [:classifier, :resolver, :escalator]
  end
end
```

### synapse_data_pipeline (NEW)
ETL and data processing orchestration.

```elixir
defmodule Synapse.DataPipeline do
  use Synapse.Domain

  signals do
    topic :pipeline_triggered
    topic :stage_completed
    topic :pipeline_failed
    topic :pipeline_succeeded
  end

  agents do
    specialist :extractor, actions: [FetchFromS3, FetchFromAPI, FetchFromDB]
    specialist :transformer, actions: [CleanData, NormalizeSchema, Aggregate]
    specialist :loader, actions: [WriteToWarehouse, UpdateCache, NotifyDownstream]
    specialist :validator, actions: [CheckSchema, CheckQuality, CheckCompleteness]
    orchestrator :pipeline_coordinator
  end
end
```

### synapse_doc_gen (NEW)
Documentation generation from code.

```elixir
defmodule Synapse.DocGen do
  use Synapse.Domain

  agents do
    specialist :analyzer, actions: [ParseAST, ExtractTypes, FindExamples]
    specialist :writer, actions: [GenerateModuleDoc, GenerateFunctionDoc]
    specialist :reviewer, actions: [CheckAccuracy, CheckCompleteness]
    orchestrator :doc_coordinator
  end
end
```

---

## Layer 5: Connectors

### synapse_github (NEW)
GitHub integration for PR workflows.

```elixir
defmodule Synapse.GitHub do
  # Webhooks → Synapse signals
  def handle_webhook(%{"action" => "opened", "pull_request" => pr}) do
    Synapse.SignalRouter.publish(:review_request, %{
      review_id: "PR-#{pr["number"]}",
      diff: fetch_diff(pr),
      # ...
    })
  end

  # Synapse signals → GitHub API
  def on_signal(:review_summary, summary) do
    post_pr_comment(summary.review_id, format_summary(summary))
  end
end
```

### synapse_slack (NEW)
Slack bot integration.

```elixir
defmodule Synapse.Slack do
  # Slack events → Synapse signals
  # Synapse signals → Slack messages
  # Interactive approval workflows
end
```

### synapse_linear / synapse_jira (NEW)
Issue tracker integrations.

### synapse_s3 / synapse_gcs (NEW)
Cloud storage triggers and actions.

---

## Layer 6: Tooling

### synapse_cli (NEW)
Command-line interface for development and operations.

```bash
# Project scaffolding
$ synapse new my_domain --template support

# Signal inspection
$ synapse signals list
$ synapse signals publish :review_request --file payload.json

# Agent management
$ synapse agents status
$ synapse agents restart :security_specialist

# Workflow debugging
$ synapse workflow trace req_abc123
$ synapse workflow replay req_abc123 --from-step :analyze

# Telemetry
$ synapse metrics
$ synapse logs --agent :coordinator --level debug
```

### synapse_ui (NEW)
Web dashboard for monitoring and debugging.

```elixir
# Phoenix LiveView dashboard
defmodule SynapseUI do
  # Real-time agent status
  # Signal flow visualization
  # Workflow execution timeline
  # Cost tracking per agent/workflow
  # Error rates and alerts
end
```

### synapse_test (NEW)
Testing utilities for domain development.

```elixir
defmodule Synapse.Test do
  # Mock agent responses
  def mock_agent(:claude, fn prompt -> "mocked response" end)

  # Signal assertions
  assert_signal_published :review_result, %{severity: :high}

  # Workflow assertions
  assert_workflow_completed :my_workflow, within: 5_000

  # Agent interaction recording/playback
  use Synapse.Test.VCR  # Record real interactions, replay in tests
end
```

### synapse_bench (NEW)
Benchmarking and load testing.

```elixir
defmodule Synapse.Bench do
  # Measure agent response times
  # Workflow throughput testing
  # Cost estimation
  # Capacity planning
end
```

---

## Layer 7: Observability

### synapse_otel (NEW)
OpenTelemetry integration.

```elixir
defmodule Synapse.OTEL do
  # Distributed tracing across agents
  # Spans for: signal publish → agent processing → workflow steps → LLM calls
  # Export to Jaeger, Honeycomb, Datadog, etc.
end
```

### synapse_prometheus (NEW)
Prometheus metrics exporter.

```elixir
# Metrics:
# - synapse_signals_published_total
# - synapse_agent_requests_total
# - synapse_workflow_duration_seconds
# - synapse_llm_tokens_total
# - synapse_llm_cost_dollars
```

---

## Package Dependency Graph

```
                    ┌─────────────────┐
                    │  Your App       │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│synapse_code_    │ │synapse_github   │ │synapse_cli      │
│review           │ │                 │ │                 │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │synapse_agent_   │
                    │core             │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│claude_agent_sdk │ │codex_sdk        │ │synapse_ollama   │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │    synapse      │
                    │    (core)       │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │      jido       │
                    └─────────────────┘
```

---

## Hex Package Matrix

| Package | Status | Priority | Description |
|---------|--------|----------|-------------|
| `jido` | ✅ Exists | - | Foundation |
| `synapse` | ✅ Exists | P0 | Core platform (needs slimming) |
| `claude_agent_sdk` | ✅ Exists | P0 | Claude Code integration |
| `codex_sdk` | ✅ Exists | P0 | OpenAI Codex integration |
| `synapse_agent_core` | 🆕 New | P1 | Unified agent interface |
| `synapse_code_review` | 📦 Extract | P1 | First domain package |
| `synapse_test` | 🆕 New | P1 | Testing utilities |
| `synapse_cli` | 🆕 New | P2 | Developer CLI |
| `synapse_github` | 🆕 New | P2 | GitHub connector |
| `synapse_slack` | 🆕 New | P2 | Slack connector |
| `synapse_ollama` | 🆕 New | P2 | Local models |
| `synapse_ui` | 🆕 New | P3 | Web dashboard |
| `synapse_otel` | 🆕 New | P3 | OpenTelemetry |
| `synapse_support` | 🆕 New | P3 | Support domain |
| `synapse_data_pipeline` | 🆕 New | P3 | ETL domain |

---

## Competitive Positioning

### vs. LangChain/LangGraph (Python)
- **Synapse advantage**: Native OTP concurrency, fault tolerance, hot code reload
- **Gap to close**: Ecosystem size, integrations, community

### vs. CrewAI (Python)
- **Synapse advantage**: Declarative config, signal-based coordination, persistence
- **Gap to close**: Ease of getting started, tutorials

### vs. AutoGen (Microsoft)
- **Synapse advantage**: Production-ready OTP patterns, workflow engine
- **Gap to close**: Multi-model orchestration patterns

### vs. Temporal (Go/multi-language)
- **Synapse advantage**: Tighter LLM integration, agent-native
- **Gap to close**: Workflow durability, enterprise features

### Unique Differentiators
1. **OTP-native**: Supervision, fault tolerance, distribution built-in
2. **Signal-driven**: True event sourcing for agent coordination
3. **Declarative agents**: No GenServer boilerplate
4. **Unified persistence**: Workflow audit trails out of the box
5. **Multi-provider agents**: Claude, Codex, Gemini, Ollama behind one interface

---

## Implementation Roadmap

### Phase 1: Foundation (Current → +2 months)
- [ ] Slim down `synapse` core (remove domains)
- [ ] Extract `synapse_code_review` as first domain package
- [ ] Create `synapse_agent_core` with unified interface
- [ ] Add adapters to `claude_agent_sdk` and `codex_sdk`
- [ ] Create `synapse_test` utilities

### Phase 2: Developer Experience (+2 → +4 months)
- [ ] Build `synapse_cli` for scaffolding and debugging
- [ ] Add `synapse_ollama` for local development
- [ ] Create comprehensive documentation site
- [ ] Build example applications

### Phase 3: Connectors (+4 → +6 months)
- [ ] `synapse_github` for PR workflows
- [ ] `synapse_slack` for notifications and approvals
- [ ] `synapse_linear` / `synapse_jira` for issue tracking

### Phase 4: Production (+6 → +9 months)
- [ ] `synapse_ui` web dashboard
- [ ] `synapse_otel` observability
- [ ] `synapse_prometheus` metrics
- [ ] Enterprise features (RBAC, audit logs, SSO)

### Phase 5: Ecosystem Growth (+9 months →)
- [ ] More domain packages
- [ ] Community contributions
- [ ] Commercial support / cloud offering
