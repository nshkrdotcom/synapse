# Phase 3+4: Domain Migration & Documentation

**Agent Task:** Coordinate two parallel sub-agents to complete domain migration and documentation.

**Version:** v0.1.1

**Prerequisites:** Phase 1 and Phase 2 must be complete.

---

## Initial Assessment Task

Before spawning sub-agents, verify Phase 1 and 2 completion:

```bash
# Verify everything compiles
mix compile --warnings-as-errors

# Verify all tests pass
mix test

# Verify Signal Registry exists
ls lib/synapse/signal/registry.ex

# Verify AgentConfig has roles support
grep -n "roles" lib/synapse/orchestrator/agent_config.ex

# Verify RunConfig uses config-driven dispatch
grep -n "get_signal_roles\|roles.request" lib/synapse/orchestrator/actions/run_config.ex

# Verify generic state keys
grep -n ":tasks" lib/synapse/orchestrator/actions/run_config.ex
```

If any verification fails, STOP and report which phase is incomplete.

---

## Sub-Agent Architecture

Spawn two sub-agents in parallel. They work on completely separate file sets:

```
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│ Sub-Agent 3: Domain Migration   │  │ Sub-Agent 4: Documentation      │
│                                 │  │                                 │
│ lib/synapse/signal/review_*.ex  │  │ docs/guides/*.md                │
│ lib/synapse/domains/**          │  │ README.md                       │
│ lib/synapse/actions/review/*    │  │ CHANGELOG.md                    │
│ lib/synapse/actions/security/*  │  │                                 │
│ lib/synapse/actions/performance/*│  │                                 │
│ priv/orchestrator_agents.exs    │  │                                 │
│                                 │  │                                 │
│ NO DOCS FILES                   │  │ NO LIB/PRIV FILES               │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

**CRITICAL: Each sub-agent may ONLY modify files in its designated area.**

---

# Sub-Agent 3: Domain Migration

## Required Reading

```
lib/synapse/signal/review_request.ex
lib/synapse/signal/review_result.ex
lib/synapse/signal/review_summary.ex
lib/synapse/signal/specialist_ready.ex
lib/synapse/signal/registry.ex
lib/synapse/actions/review/classify_change.ex
lib/synapse/actions/review/generate_summary.ex
lib/synapse/actions/review/decide_escalation.ex
lib/synapse/actions/security/check_sql_injection.ex
lib/synapse/actions/security/check_xss.ex
lib/synapse/actions/security/check_auth_issues.ex
lib/synapse/actions/performance/check_complexity.ex
lib/synapse/actions/performance/check_memory_usage.ex
lib/synapse/actions/performance/profile_hot_path.ex
priv/orchestrator_agents.exs
test/synapse/actions/**/*
docs/20251129/domain-agnostic-signals/PLAN.md
```

## Context

The review-specific signal schemas and actions should be moved to an optional domain module. This allows users to:
1. Use Synapse without code review concepts
2. Opt-in to code review domain by calling `Synapse.Domains.CodeReview.register/0`
3. See the domain as an example for building their own domains

## Task

### Step 1: Create Domain Module Structure

Create directory structure:
```
lib/synapse/domains/
lib/synapse/domains/code_review/
lib/synapse/domains/code_review/signals/
lib/synapse/domains/code_review/actions/
lib/synapse/domains/code_review/actions/review/
lib/synapse/domains/code_review/actions/security/
lib/synapse/domains/code_review/actions/performance/
```

### Step 2: Create Domain Registration Module

Create `lib/synapse/domains/code_review.ex`:

```elixir
defmodule Synapse.Domains.CodeReview do
  @moduledoc """
  Code review domain for Synapse.

  This module registers code-review-specific signal topics and provides
  pre-built actions for security and performance analysis of code changes.

  ## Usage

  Register the domain in your application startup:

      # In application.ex or runtime config
      Synapse.Domains.CodeReview.register()

  Or in config:

      config :synapse, :domains, [Synapse.Domains.CodeReview]

  ## Signals

  This domain registers the following signal topics:

  - `:review_request` - Incoming code review requests
  - `:review_result` - Results from specialist agents
  - `:review_summary` - Aggregated review summaries
  - `:specialist_ready` - Specialist availability notifications

  ## Actions

  Available actions for building review workflows:

  ### Review Actions
  - `Synapse.Domains.CodeReview.Actions.ClassifyChange`
  - `Synapse.Domains.CodeReview.Actions.GenerateSummary`
  - `Synapse.Domains.CodeReview.Actions.DecideEscalation`

  ### Security Actions
  - `Synapse.Domains.CodeReview.Actions.CheckSQLInjection`
  - `Synapse.Domains.CodeReview.Actions.CheckXSS`
  - `Synapse.Domains.CodeReview.Actions.CheckAuthIssues`

  ### Performance Actions
  - `Synapse.Domains.CodeReview.Actions.CheckComplexity`
  - `Synapse.Domains.CodeReview.Actions.CheckMemoryUsage`
  - `Synapse.Domains.CodeReview.Actions.ProfileHotPath`
  """

  alias Synapse.Signal

  @doc """
  Registers all code review signal topics with the Signal Registry.

  Call this function during application startup to enable code review signals.

  ## Example

      # In your application.ex start/2 function:
      def start(_type, _args) do
        Synapse.Domains.CodeReview.register()

        children = [
          # ...
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  """
  @spec register() :: :ok
  def register do
    register_review_request()
    register_review_result()
    register_review_summary()
    register_specialist_ready()
    :ok
  end

  @doc """
  Returns the list of signal topics registered by this domain.
  """
  @spec topics() :: [atom()]
  def topics do
    [:review_request, :review_result, :review_summary, :specialist_ready]
  end

  @doc """
  Returns all action modules provided by this domain.
  """
  @spec actions() :: [module()]
  def actions do
    [
      # Review
      __MODULE__.Actions.ClassifyChange,
      __MODULE__.Actions.GenerateSummary,
      __MODULE__.Actions.DecideEscalation,
      # Security
      __MODULE__.Actions.CheckSQLInjection,
      __MODULE__.Actions.CheckXSS,
      __MODULE__.Actions.CheckAuthIssues,
      # Performance
      __MODULE__.Actions.CheckComplexity,
      __MODULE__.Actions.CheckMemoryUsage,
      __MODULE__.Actions.ProfileHotPath
    ]
  end

  defp register_review_request do
    Signal.register_topic(:review_request,
      type: "review.request",
      schema: [
        review_id: [type: :string, required: true, doc: "Unique identifier for the review"],
        diff: [type: :string, default: "", doc: "Unified diff or snippet under review"],
        metadata: [type: :map, default: %{}, doc: "Arbitrary metadata describing the review target"],
        files_changed: [type: :integer, default: 0, doc: "Count of files changed in the review"],
        labels: [type: {:list, :string}, default: [], doc: "Labels or tags attached to the review"],
        intent: [type: :string, default: "feature", doc: "Intent label used for routing"],
        risk_factor: [type: :float, default: 0.0, doc: "Risk multiplier used during classification"],
        files: [type: {:list, :string}, default: [], doc: "List of files referenced by the review"],
        language: [type: :string, default: "elixir", doc: "Primary language hint for the review"]
      ]
    )
  end

  defp register_review_result do
    Signal.register_topic(:review_result,
      type: "review.result",
      schema: [
        review_id: [type: :string, required: true, doc: "Review identifier the findings belong to"],
        agent: [type: :string, required: true, doc: "Logical specialist identifier"],
        confidence: [type: :float, default: 0.0, doc: "Confidence score for the findings"],
        findings: [type: {:list, :map}, default: [], doc: "List of findings detected by the specialist"],
        should_escalate: [type: :boolean, default: false, doc: "Signals whether human escalation is recommended"],
        metadata: [type: :map, default: %{}, doc: "Additional execution metadata emitted by the specialist"]
      ]
    )
  end

  defp register_review_summary do
    Signal.register_topic(:review_summary,
      type: "review.summary",
      schema: [
        review_id: [type: :string, required: true, doc: "Review identifier"],
        status: [type: :atom, default: :complete, doc: "Overall status for the review workflow"],
        severity: [type: :atom, default: :none, doc: "Max severity across all findings"],
        findings: [type: {:list, :map}, default: [], doc: "Combined findings ordered by severity"],
        recommendations: [type: {:list, :any}, default: [], doc: "Recommended actions for follow-up"],
        escalations: [type: {:list, :string}, default: [], doc: "Reason(s) for triggering escalation"],
        metadata: [type: :map, default: %{}, doc: "Coordinator metadata (decision path, runtime stats, etc.)"]
      ]
    )
  end

  defp register_specialist_ready do
    Signal.register_topic(:specialist_ready,
      type: "review.specialist_ready",
      schema: [
        specialist_id: [type: :string, required: true, doc: "Specialist identifier"],
        capabilities: [type: {:list, :string}, default: [], doc: "List of capabilities this specialist provides"]
      ]
    )
  end
end
```

### Step 3: Move Action Modules

Move each action module to the domain namespace. Update the module name and any internal references.

#### Example: Move ClassifyChange

From: `lib/synapse/actions/review/classify_change.ex`
To: `lib/synapse/domains/code_review/actions/classify_change.ex`

```elixir
defmodule Synapse.Domains.CodeReview.Actions.ClassifyChange do
  @moduledoc """
  Classifies a code review request to determine the appropriate review path.

  Returns either `:fast_path` for small, low-risk changes or `:deep_review`
  for changes requiring thorough specialist analysis.
  """

  use Jido.Action,
    name: "code_review.classify_change",
    description: "Determines review path based on change characteristics",
    schema: [
      # ... same schema as before ...
    ]

  # ... rest of implementation unchanged ...
end
```

#### Create Alias Modules for Backward Compatibility

For each moved module, leave a deprecated alias at the old location.

Create `lib/synapse/actions/review/classify_change.ex` (new content):

```elixir
defmodule Synapse.Actions.Review.ClassifyChange do
  @moduledoc """
  Deprecated: Use `Synapse.Domains.CodeReview.Actions.ClassifyChange` instead.

  This module is maintained for backward compatibility and will be removed
  in a future release.
  """

  @deprecated "Use Synapse.Domains.CodeReview.Actions.ClassifyChange instead"
  defdelegate run(params, context), to: Synapse.Domains.CodeReview.Actions.ClassifyChange

  # Forward all other callbacks
  defdelegate schema(), to: Synapse.Domains.CodeReview.Actions.ClassifyChange
end
```

Repeat for ALL action modules:
- `lib/synapse/actions/review/generate_summary.ex`
- `lib/synapse/actions/review/decide_escalation.ex`
- `lib/synapse/actions/security/check_sql_injection.ex`
- `lib/synapse/actions/security/check_xss.ex`
- `lib/synapse/actions/security/check_auth_issues.ex`
- `lib/synapse/actions/performance/check_complexity.ex`
- `lib/synapse/actions/performance/check_memory_usage.ex`
- `lib/synapse/actions/performance/profile_hot_path.ex`

### Step 4: Update Signal Registry Legacy Support

The Signal Registry should no longer auto-register review signals. Instead, they're registered when `Synapse.Domains.CodeReview.register/0` is called.

Modify `lib/synapse/signal/registry.ex`:

Remove or disable the `register_legacy_signals/1` function. The legacy signals should only be available when the CodeReview domain is explicitly registered.

Add a config option to auto-register domains:

```elixir
def init(opts) do
  # ... existing init code ...

  # Auto-register configured domains
  domains = Application.get_env(:synapse, :domains, [])
  Enum.each(domains, fn domain ->
    if function_exported?(domain, :register, 0) do
      domain.register()
    end
  end)

  {:ok, state}
end
```

Update `config/config.exs` to auto-register CodeReview domain for backward compatibility:

```elixir
# Auto-register domains on startup (for backward compatibility)
config :synapse, :domains, [Synapse.Domains.CodeReview]
```

### Step 5: Update priv/orchestrator_agents.exs

Update the example configuration to:
1. Show generic signals as the primary example
2. Include code review domain as an alternative example

```elixir
# Declarative agent configuration for Synapse Orchestrator
#
# This configuration demonstrates two approaches:
# 1. Generic signals (recommended for new domains)
# 2. Code review domain signals (for code review use cases)
#
# Usage:
#   {Synapse.Orchestrator.Runtime,
#     config_source: {:priv, "orchestrator_agents.exs"},
#     bus: :synapse_bus,
#     registry: :synapse_registry
#   }

# ============================================================================
# EXAMPLE 1: Generic Signals (Domain-Agnostic)
# ============================================================================
#
# Use these patterns for custom domains. Replace with your own actions.
#
# [
#   %{
#     id: :worker_a,
#     type: :specialist,
#     actions: [MyApp.Actions.ProcessTask],
#     signals: %{
#       subscribes: [:task_request],
#       emits: [:task_result]
#     }
#   },
#   %{
#     id: :coordinator,
#     type: :orchestrator,
#     signals: %{
#       subscribes: [:task_request, :task_result],
#       emits: [:task_summary],
#       roles: %{
#         request: :task_request,
#         result: :task_result,
#         summary: :task_summary
#       }
#     },
#     orchestration: %{
#       classify_fn: fn data -> %{path: :default} end,
#       spawn_specialists: [:worker_a],
#       aggregation_fn: fn results, state ->
#         %{task_id: state.task_id, status: :complete, results: results}
#       end
#     }
#   }
# ]

# ============================================================================
# EXAMPLE 2: Code Review Domain
# ============================================================================
#
# Requires: Synapse.Domains.CodeReview domain to be registered
# (auto-registered by default via config :synapse, :domains)

alias Synapse.Domains.CodeReview.Actions.{
  ClassifyChange,
  CheckSQLInjection,
  CheckXSS,
  CheckAuthIssues,
  CheckComplexity,
  CheckMemoryUsage,
  ProfileHotPath
}

# Helper functions for the code review domain
severity_score = fn
  :critical -> 4
  :high -> 3
  :medium -> 2
  :low -> 1
  _ -> 0
end

dominant_severity = fn findings ->
  Enum.reduce(findings, :none, fn finding, acc ->
    severity = Map.get(finding, :severity, :none)
    if severity_score.(severity) > severity_score.(acc), do: severity, else: acc
  end)
end

calculate_confidence = fn
  [] -> 1.0
  findings ->
    case length(findings) do
      n when n < 3 -> 0.9
      n when n < 5 -> 0.8
      _ -> 0.7
    end
end

build_recommendations = fn
  [] -> ["No issues found"]
  findings ->
    findings
    |> Enum.map(& &1.recommendation)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
end

resolve_conflicts = fn result, task_state ->
  result_findings = Map.get(result, :findings, [])
  result_severity = dominant_severity.(result_findings)

  prior_results = Enum.reject(task_state.results, &(&1.agent == result.agent))

  conflicting = Enum.filter(prior_results, fn existing ->
    existing_severity = dominant_severity.(Map.get(existing, :findings, []))
    existing_severity != result_severity
  end)

  if conflicting == [] do
    task_state
  else
    ranking = [{result.agent, result_severity} |
      Enum.map(conflicting, fn existing ->
        {existing.agent, dominant_severity.(Map.get(existing, :findings, []))}
      end)]

    {winning_agent, winning_severity} =
      Enum.max_by(ranking, fn {_agent, severity} -> severity_score.(severity) end)

    conflict_agents = (Enum.map(conflicting, & &1.agent) ++ [result.agent])
      |> Enum.uniq() |> Enum.sort()

    update_in(task_state, [:metadata, :negotiations], fn negotiations ->
      [%{
        agents: conflict_agents,
        resolution: :prefer_highest_severity,
        winning_agent: winning_agent,
        winning_severity: winning_severity
      } | List.wrap(negotiations)]
    end)
  end
end

[
  # Security Specialist Agent
  %{
    id: :security_specialist,
    type: :specialist,
    actions: [CheckSQLInjection, CheckXSS, CheckAuthIssues],
    signals: %{
      subscribes: [:review_request],
      emits: [:review_result]
    },
    result_builder: fn results, signal_payload ->
      findings =
        results
        |> Enum.filter(&match?({:ok, _, %{findings: _}}, &1))
        |> Enum.flat_map(fn {:ok, _action, %{findings: findings}} -> findings end)

      %{
        review_id: signal_payload[:review_id] || signal_payload[:task_id],
        agent: "security_specialist",
        confidence: calculate_confidence.(findings),
        findings: findings,
        should_escalate: Enum.any?(findings, &(&1.severity == :high)),
        metadata: %{actions_run: [CheckSQLInjection, CheckXSS, CheckAuthIssues]}
      }
    end,
    metadata: %{
      category: "security",
      description: "Analyzes code for security vulnerabilities"
    }
  },

  # Performance Specialist Agent
  %{
    id: :performance_specialist,
    type: :specialist,
    actions: [CheckComplexity, CheckMemoryUsage, ProfileHotPath],
    signals: %{
      subscribes: [:review_request],
      emits: [:review_result]
    },
    result_builder: fn results, signal_payload ->
      findings =
        results
        |> Enum.filter(&match?({:ok, _, %{findings: _}}, &1))
        |> Enum.flat_map(fn {:ok, _action, %{findings: findings}} -> findings end)

      %{
        review_id: signal_payload[:review_id] || signal_payload[:task_id],
        agent: "performance_specialist",
        confidence: calculate_confidence.(findings),
        findings: findings,
        should_escalate: Enum.any?(findings, &(&1.severity in [:high, :medium])),
        metadata: %{actions_run: [CheckComplexity, CheckMemoryUsage, ProfileHotPath]}
      }
    end,
    metadata: %{
      category: "performance",
      description: "Analyzes code for performance issues"
    }
  },

  # Coordinator Agent
  %{
    id: :coordinator,
    type: :orchestrator,
    actions: [ClassifyChange],
    orchestration: %{
      classify_fn: fn task_data ->
        files_changed = Map.get(task_data, :files_changed, 0)
        labels = Map.get(task_data, :labels, [])

        cond do
          files_changed > 50 -> %{path: :dispatched, rationale: "Large change"}
          "security" in labels -> %{path: :dispatched, rationale: "Security label"}
          "performance" in labels -> %{path: :dispatched, rationale: "Performance label"}
          files_changed < 5 -> %{path: :routed, rationale: "Small change"}
          true -> %{path: :dispatched, rationale: "Default"}
        end
      end,
      spawn_specialists: [:security_specialist, :performance_specialist],
      aggregation_fn: fn specialist_results, task_state ->
        all_findings = Enum.flat_map(specialist_results, & &1.findings)
        max_severity = if all_findings == [], do: :none, else: dominant_severity.(all_findings)

        %{
          review_id: task_state.task_id,
          status: :complete,
          severity: max_severity,
          findings: all_findings,
          recommendations: build_recommendations.(all_findings),
          escalations: [],
          metadata: %{
            decision_path: task_state.classification_path,
            specialists_resolved: task_state.metadata[:specialists_resolved] || [],
            duration_ms: task_state.metadata[:duration_ms] || 0,
            negotiations: task_state.metadata[:negotiations] || []
          }
        }
      end,
      negotiate_fn: resolve_conflicts
    },
    signals: %{
      subscribes: [:review_request, :review_result],
      emits: [:review_summary],
      roles: %{
        request: :review_request,
        result: :review_result,
        summary: :review_summary
      }
    },
    metadata: %{
      category: "orchestration",
      description: "Coordinates multi-agent code reviews"
    }
  }
]
```

### Step 6: Update Tests

Move tests alongside the domain:

Create `test/synapse/domains/code_review_test.exs`:

```elixir
defmodule Synapse.Domains.CodeReviewTest do
  use ExUnit.Case, async: false

  alias Synapse.Domains.CodeReview
  alias Synapse.Signal

  describe "register/0" do
    test "registers all code review signal topics" do
      # Unregister if already registered from previous test
      # (Registry should handle this gracefully)

      assert :ok = CodeReview.register()

      # Verify all topics are registered
      assert :review_request in Signal.topics()
      assert :review_result in Signal.topics()
      assert :review_summary in Signal.topics()
      assert :specialist_ready in Signal.topics()
    end

    test "topics have correct wire types" do
      CodeReview.register()

      assert Signal.type(:review_request) == "review.request"
      assert Signal.type(:review_result) == "review.result"
      assert Signal.type(:review_summary) == "review.summary"
    end

    test "can validate review_request payload" do
      CodeReview.register()

      payload = %{review_id: "PR-123", diff: "some diff"}
      result = Signal.validate!(:review_request, payload)

      assert result.review_id == "PR-123"
      assert result.diff == "some diff"
      assert result.files_changed == 0  # default
    end
  end

  describe "topics/0" do
    test "returns list of domain topics" do
      topics = CodeReview.topics()

      assert :review_request in topics
      assert :review_result in topics
      assert :review_summary in topics
      assert :specialist_ready in topics
    end
  end

  describe "actions/0" do
    test "returns list of domain actions" do
      actions = CodeReview.actions()

      assert Synapse.Domains.CodeReview.Actions.ClassifyChange in actions
      assert Synapse.Domains.CodeReview.Actions.CheckSQLInjection in actions
    end
  end
end
```

### Step 7: Delete Old Signal Schema Files

After verifying everything works, the old signal schema files can be deleted since signals are now registered dynamically:

- `lib/synapse/signal/review_request.ex` - DELETE (or keep as documentation)
- `lib/synapse/signal/review_result.ex` - DELETE
- `lib/synapse/signal/review_summary.ex` - DELETE
- `lib/synapse/signal/specialist_ready.ex` - DELETE

**Alternative:** Keep them but mark as deprecated documentation:

```elixir
defmodule Synapse.Signal.ReviewRequest do
  @moduledoc """
  DEPRECATED: This module is no longer used.

  Review request signals are now registered dynamically via
  `Synapse.Domains.CodeReview.register/0`.

  See `Synapse.Domains.CodeReview` for the current schema definition.
  """

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def schema, do: raise "This module is deprecated"
end
```

### Step 8: Run Tests

```bash
mix test
mix compile --warnings-as-errors
```

## Files to Create/Modify/Delete

| File | Action |
|------|--------|
| `lib/synapse/domains/code_review.ex` | CREATE |
| `lib/synapse/domains/code_review/actions/classify_change.ex` | CREATE (move from actions/review/) |
| `lib/synapse/domains/code_review/actions/generate_summary.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/decide_escalation.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/check_sql_injection.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/check_xss.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/check_auth_issues.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/check_complexity.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/check_memory_usage.ex` | CREATE (move) |
| `lib/synapse/domains/code_review/actions/profile_hot_path.ex` | CREATE (move) |
| `lib/synapse/actions/review/*.ex` | MODIFY (deprecated aliases) |
| `lib/synapse/actions/security/*.ex` | MODIFY (deprecated aliases) |
| `lib/synapse/actions/performance/*.ex` | MODIFY (deprecated aliases) |
| `lib/synapse/signal/review_*.ex` | DELETE or DEPRECATE |
| `lib/synapse/signal/registry.ex` | MODIFY (remove legacy auto-register) |
| `priv/orchestrator_agents.exs` | MODIFY (update examples) |
| `config/config.exs` | MODIFY (add :domains config) |
| `test/synapse/domains/code_review_test.exs` | CREATE |

## Deliverables

- [ ] `Synapse.Domains.CodeReview` module with `register/0`
- [ ] All actions moved to domain namespace
- [ ] Backward-compatible aliases at old locations
- [ ] Signal schemas removed (registered dynamically)
- [ ] Updated `priv/orchestrator_agents.exs` with generic + domain examples
- [ ] Domain auto-registration via config
- [ ] All tests pass

---

# Sub-Agent 4: Documentation

## Required Reading

```
README.md
CHANGELOG.md
docs/20251129/domain-agnostic-signals/PLAN.md
lib/synapse/signal.ex (understand new API)
lib/synapse/signal/registry.ex (understand registration)
lib/synapse/orchestrator/agent_config.ex (understand roles)
lib/synapse/domains/code_review.ex (understand domain pattern)
```

## Context

Documentation needs to reflect the new domain-agnostic architecture:
1. Custom signal registration
2. Signal roles in agent config
3. Domain pattern for organizing signals and actions
4. Migration guide for existing users

## Task

### Step 1: Create Custom Domains Guide

Create `docs/guides/custom-domains.md`:

```markdown
# Custom Domains Guide

Synapse is a domain-agnostic multi-agent orchestration framework. While it ships
with a code review domain as an example, you can define custom domains for any
use case: customer support, document processing, data pipelines, and more.

## Quick Start

### 1. Define Your Signals

Register custom signal topics in your application config or at runtime:

\`\`\`elixir
# config/config.exs
config :synapse, Synapse.Signal.Registry,
  topics: [
    ticket_created: [
      type: "support.ticket.created",
      schema: [
        ticket_id: [type: :string, required: true],
        customer_id: [type: :string, required: true],
        subject: [type: :string, required: true],
        priority: [type: {:in, [:low, :medium, :high, :critical]}, default: :medium],
        tags: [type: {:list, :string}, default: []]
      ]
    ],
    ticket_analyzed: [
      type: "support.ticket.analyzed",
      schema: [
        ticket_id: [type: :string, required: true],
        agent: [type: :string, required: true],
        category: [type: :string],
        sentiment: [type: {:in, [:positive, :neutral, :negative]}],
        suggested_response: [type: :string]
      ]
    ],
    ticket_resolved: [
      type: "support.ticket.resolved",
      schema: [
        ticket_id: [type: :string, required: true],
        resolution: [type: :string],
        satisfaction_score: [type: :float]
      ]
    ]
  ]
\`\`\`

Or register at runtime:

\`\`\`elixir
Synapse.Signal.register_topic(:my_event,
  type: "my.domain.event",
  schema: [
    id: [type: :string, required: true],
    payload: [type: :map, default: %{}]
  ]
)
\`\`\`

### 2. Create Your Actions

Define Jido actions for your domain logic:

\`\`\`elixir
defmodule MyApp.Actions.AnalyzeSentiment do
  use Jido.Action,
    name: "analyze_sentiment",
    description: "Analyzes customer message sentiment",
    schema: [
      message: [type: :string, required: true]
    ]

  @impl true
  def run(%{message: message}, _context) do
    # Your sentiment analysis logic
    sentiment = analyze(message)
    {:ok, %{sentiment: sentiment, confidence: 0.95}}
  end
end
\`\`\`

### 3. Configure Agents

Define specialists and coordinator using your signals:

\`\`\`elixir
# priv/orchestrator_agents.exs
[
  %{
    id: :sentiment_analyzer,
    type: :specialist,
    actions: [MyApp.Actions.AnalyzeSentiment],
    signals: %{
      subscribes: [:ticket_created],
      emits: [:ticket_analyzed]
    },
    result_builder: fn results, signal_payload ->
      %{
        ticket_id: signal_payload.ticket_id,
        agent: "sentiment_analyzer",
        # ... build result from action outputs
      }
    end
  },

  %{
    id: :support_coordinator,
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
      classify_fn: fn ticket ->
        if ticket.priority == :critical do
          %{path: :urgent}
        else
          %{path: :normal}
        end
      end,
      spawn_specialists: [:sentiment_analyzer, :category_classifier],
      aggregation_fn: fn results, state ->
        %{
          ticket_id: state.task_id,
          resolution: summarize_results(results),
          status: :resolved
        }
      end
    }
  }
]
\`\`\`

## Creating a Domain Module

For reusable domains, create a domain module:

\`\`\`elixir
defmodule MyApp.Domains.Support do
  @moduledoc "Customer support domain for Synapse"

  alias Synapse.Signal

  def register do
    Signal.register_topic(:ticket_created, ...)
    Signal.register_topic(:ticket_analyzed, ...)
    Signal.register_topic(:ticket_resolved, ...)
    :ok
  end

  def topics, do: [:ticket_created, :ticket_analyzed, :ticket_resolved]
end
\`\`\`

Then register in your application:

\`\`\`elixir
# application.ex
def start(_type, _args) do
  MyApp.Domains.Support.register()
  # ...
end
\`\`\`

Or via config:

\`\`\`elixir
config :synapse, :domains, [MyApp.Domains.Support]
\`\`\`

## Signal Schema Reference

Schemas use NimbleOptions syntax:

| Type | Example |
|------|---------|
| `:string` | `name: [type: :string]` |
| `:integer` | `count: [type: :integer]` |
| `:float` | `score: [type: :float]` |
| `:boolean` | `active: [type: :boolean]` |
| `:atom` | `status: [type: :atom]` |
| `:map` | `metadata: [type: :map]` |
| `{:list, type}` | `tags: [type: {:list, :string}]` |
| `{:in, list}` | `priority: [type: {:in, [:low, :high]}]` |

Options:
- `required: true` - Field must be present
- `default: value` - Default if not provided
- `doc: "description"` - Documentation string

## Example Domains

### Document Processing

\`\`\`elixir
topics: [
  document_submitted: [
    type: "docs.submitted",
    schema: [
      doc_id: [type: :string, required: true],
      content_type: [type: :string, required: true],
      content: [type: :string]
    ]
  ],
  document_processed: [
    type: "docs.processed",
    schema: [
      doc_id: [type: :string, required: true],
      extracted_text: [type: :string],
      entities: [type: {:list, :map}]
    ]
  ]
]
\`\`\`

### Data Pipeline

\`\`\`elixir
topics: [
  job_queued: [
    type: "pipeline.job.queued",
    schema: [
      job_id: [type: :string, required: true],
      source: [type: :string, required: true],
      destination: [type: :string, required: true],
      transform: [type: :atom]
    ]
  ],
  job_completed: [
    type: "pipeline.job.completed",
    schema: [
      job_id: [type: :string, required: true],
      records_processed: [type: :integer],
      duration_ms: [type: :integer]
    ]
  ]
]
\`\`\`

## See Also

- [Signal API Reference](../api/signal.md)
- [Agent Configuration](../api/agent-config.md)
- [Code Review Domain](../domains/code-review.md)
\`\`\`

### Step 2: Create Migration Guide

Create `docs/guides/migration-0.2.md`:

```markdown
# Migration Guide: v0.1.x to v0.2.x

This guide covers migrating from Synapse v0.1.x (code-review-specific) to
v0.2.x (domain-agnostic).

## Overview of Changes

### Signal Layer

**Before (v0.1.x):**
- Hardcoded signal topics: `:review_request`, `:review_result`, `:review_summary`
- Signal schemas defined as modules in `lib/synapse/signal/`

**After (v0.2.x):**
- Dynamic signal registry with config-based or runtime registration
- Generic core signals: `:task_request`, `:task_result`, `:task_summary`
- Code review signals available via `Synapse.Domains.CodeReview`

### Agent Configuration

**Before:**
\`\`\`elixir
signals: %{
  subscribes: [:review_request],
  emits: [:review_result]
}
\`\`\`

**After:**
\`\`\`elixir
signals: %{
  subscribes: [:review_request],
  emits: [:review_result],
  roles: %{
    request: :review_request,
    result: :review_result,
    summary: :review_summary
  }
}
\`\`\`

### Action Locations

**Before:**
- `Synapse.Actions.Review.ClassifyChange`
- `Synapse.Actions.Security.CheckSQLInjection`

**After:**
- `Synapse.Domains.CodeReview.Actions.ClassifyChange`
- `Synapse.Domains.CodeReview.Actions.CheckSQLInjection`

(Old locations still work but are deprecated)

## Migration Steps

### Step 1: Update Dependencies

\`\`\`elixir
# mix.exs
{:synapse, "~> 0.2.0"}
\`\`\`

### Step 2: Register Code Review Domain

If you're using code review signals, explicitly register the domain:

\`\`\`elixir
# application.ex
def start(_type, _args) do
  # Register code review domain
  Synapse.Domains.CodeReview.register()

  children = [
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
\`\`\`

Or via config (recommended):

\`\`\`elixir
# config/config.exs
config :synapse, :domains, [Synapse.Domains.CodeReview]
\`\`\`

### Step 3: Update Action References (Optional)

Update action module references to new locations:

\`\`\`elixir
# Before
alias Synapse.Actions.Security.CheckSQLInjection

# After
alias Synapse.Domains.CodeReview.Actions.CheckSQLInjection
\`\`\`

The old locations work but emit deprecation warnings.

### Step 4: Add Signal Roles (Recommended)

For orchestrator agents, explicitly define signal roles:

\`\`\`elixir
%{
  id: :coordinator,
  type: :orchestrator,
  signals: %{
    subscribes: [:review_request, :review_result],
    emits: [:review_summary],
    # NEW: explicit roles
    roles: %{
      request: :review_request,
      result: :review_result,
      summary: :review_summary
    }
  },
  # ...
}
\`\`\`

If roles aren't specified, they're inferred from topic names.

## Breaking Changes

### Removed

- `Synapse.Signal.ReviewRequest` module (use dynamic registration)
- `Synapse.Signal.ReviewResult` module
- `Synapse.Signal.ReviewSummary` module
- `Synapse.Signal.SpecialistReady` module

### Changed

- `Synapse.Signal.topics/0` returns dynamically registered topics
- `Synapse.Signal.type/1` looks up from registry
- Orchestrator state uses `:tasks` instead of `:reviews`

### Deprecated

- `Synapse.Actions.Review.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Security.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Performance.*` (use `Synapse.Domains.CodeReview.Actions.*`)

## Compatibility Mode

For gradual migration, enable legacy signal support:

\`\`\`elixir
# config/config.exs
config :synapse, :domains, [Synapse.Domains.CodeReview]
\`\`\`

This registers the review signals automatically, maintaining v0.1.x behavior.

## Getting Help

- [Custom Domains Guide](./custom-domains.md)
- [GitHub Issues](https://github.com/your-org/synapse/issues)
\`\`\`

### Step 3: Update README.md

Update `README.md` with:

1. Change version to `0.1.1`
2. Update description to emphasize domain-agnostic nature
3. Add custom domains section
4. Update examples

Key sections to update:

```markdown
# Synapse

Version: v0.1.1 (2025-11-29)

Synapse is a headless, declarative multi-agent orchestration framework. It provides
a signal bus API, workflow engine with Postgres persistence, and configurable
agent runtime for building domain-specific multi-agent systems.

While Synapse includes a code review domain as a reference implementation, you can
define custom domains for any use case: customer support, document processing,
data pipelines, IoT coordination, and more.

## Highlights

- **Domain-agnostic** signal registry with runtime topic registration
- Declarative orchestrator runtime (no GenServer boilerplate)
- Signal bus with typed topics and contract enforcement
- Configurable signal roles for custom orchestration patterns
- Workflow engine with persistence and audit trail
- LLM gateway with OpenAI and Gemini providers
- Telemetry throughout

## Quick Start

[... existing quick start ...]

## Custom Domains

Define your own signal topics:

\`\`\`elixir
# config/config.exs
config :synapse, Synapse.Signal.Registry,
  topics: [
    my_request: [
      type: "my.domain.request",
      schema: [
        id: [type: :string, required: true],
        payload: [type: :map, default: %{}]
      ]
    ]
  ]
\`\`\`

Or register at runtime:

\`\`\`elixir
Synapse.Signal.register_topic(:custom_event,
  type: "custom.event",
  schema: [id: [type: :string, required: true]]
)
\`\`\`

See [Custom Domains Guide](docs/guides/custom-domains.md) for full documentation.

## Code Review Domain

For code review use cases, register the built-in domain:

\`\`\`elixir
# config/config.exs
config :synapse, :domains, [Synapse.Domains.CodeReview]
\`\`\`

This registers `:review_request`, `:review_result`, and `:review_summary` signals
with pre-built security and performance analysis actions.
```

### Step 4: Update CHANGELOG.md

Ensure CHANGELOG.md has complete v0.1.1 entry:

```markdown
# Changelog

## [0.1.1] - 2025-11-29

### Added
- **Domain-agnostic signal layer**: Dynamic signal registry replacing hardcoded topics
- `Synapse.Signal.Registry` for runtime topic management
- `Synapse.Signal.register_topic/2` for runtime signal registration
- Configuration-based signal topic definition
- Generic core signals: `:task_request`, `:task_result`, `:task_summary`, `:worker_ready`
- Signal `roles` configuration for orchestrator agents
- `initial_state` support in orchestrator agent config
- `Synapse.Domains.CodeReview` module encapsulating code review functionality
- Custom domains documentation guide
- Migration guide from v0.1.0

### Changed
- `Synapse.Signal` delegates to `Synapse.Signal.Registry`
- `SignalRouter` works with dynamically registered topics
- `AgentConfig` validates topics against dynamic registry and supports roles
- `RunConfig` uses config-driven signal dispatch
- Orchestrator state uses generic keys (`tasks` instead of `reviews`)
- Code review actions moved to `Synapse.Domains.CodeReview.Actions.*`

### Deprecated
- `Synapse.Signal.ReviewRequest` module (use dynamic registration)
- `Synapse.Signal.ReviewResult` module
- `Synapse.Signal.ReviewSummary` module
- `Synapse.Actions.Review.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Security.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Performance.*` (use `Synapse.Domains.CodeReview.Actions.*`)

### Migration
- Existing code review users should add `config :synapse, :domains, [Synapse.Domains.CodeReview]`
- See [Migration Guide](docs/guides/migration-0.2.md) for details

## [0.1.0] - 2025-11-11

Initial release.
```

### Step 5: Create Directory Structure

```bash
mkdir -p docs/guides
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `docs/guides/custom-domains.md` | CREATE |
| `docs/guides/migration-0.2.md` | CREATE |
| `README.md` | MODIFY |
| `CHANGELOG.md` | MODIFY |

## Deliverables

- [ ] Custom domains guide with examples for 3+ domains
- [ ] Migration guide with before/after code samples
- [ ] Updated README reflecting domain-agnostic nature
- [ ] Complete CHANGELOG entry for v0.1.1
- [ ] All documentation uses consistent version (0.1.1)

---

# Coordinator Agent: Final Steps

After both sub-agents complete, run full validation:

```bash
# Full test suite
mix test

# Compiler warnings
mix compile --warnings-as-errors

# Dialyzer
mix dialyzer

# Format check
mix format --check-formatted

# Verify documentation builds (if using ex_doc)
mix docs
```

## Final Checklist

- [ ] All tests pass: `mix test`
- [ ] No compiler warnings: `mix compile --warnings-as-errors`
- [ ] Dialyzer passes: `mix dialyzer`
- [ ] Format check passes: `mix format --check-formatted`
- [ ] `Synapse.Domains.CodeReview` exists and works
- [ ] All actions moved to domain namespace
- [ ] Backward compatibility aliases work
- [ ] `priv/orchestrator_agents.exs` updated
- [ ] `docs/guides/custom-domains.md` exists
- [ ] `docs/guides/migration-0.2.md` exists
- [ ] `README.md` reflects v0.1.1 with domain-agnostic messaging
- [ ] `CHANGELOG.md` has complete v0.1.1 entry

---

## Success Criteria

Phase 3+4 is complete when:

1. Code review domain is properly encapsulated in `Synapse.Domains.CodeReview`
2. Users can define custom domains without modifying Synapse source
3. Backward compatibility is maintained via deprecated aliases
4. Documentation clearly explains the domain-agnostic architecture
5. Migration path is documented for v0.1.0 users
6. `mix test` - ALL TESTS PASSING
7. `mix compile --warnings-as-errors` - NO WARNINGS
8. `mix dialyzer` - NO ERRORS
9. `mix format --check-formatted` - PASSES
10. CHANGELOG.md and README.md updated for v0.1.1
