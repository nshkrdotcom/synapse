# Custom Domains Guide

Synapse is a domain-agnostic multi-agent orchestration framework. While it ships
with a code review domain as an example, you can define custom domains for any
use case: customer support, document processing, data pipelines, and more.

## Quick Start

### 1. Define Your Signals

Register custom signal topics in your application config or at runtime:

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
```

Or register at runtime:

```elixir
Synapse.Signal.register_topic(:my_event,
  type: "my.domain.event",
  schema: [
    id: [type: :string, required: true],
    payload: [type: :map, default: %{}]
  ]
)
```

### 2. Create Your Actions

Define Jido actions for your domain logic:

```elixir
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
```

### 3. Configure Agents

Define specialists and coordinator using your signals:

```elixir
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
```

## Creating a Domain Module

For reusable domains, create a domain module:

```elixir
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
```

Then register in your application:

```elixir
# application.ex
def start(_type, _args) do
  MyApp.Domains.Support.register()
  # ...
end
```

Or via config:

```elixir
config :synapse, :domains, [MyApp.Domains.Support]
```

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

```elixir
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
```

### Data Pipeline

```elixir
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
```

## See Also

- [Signal registry overview in README](../../README.md#custom-domains)
- [Agent configuration (roles) in README](../../README.md#agent-configuration)
- [Code review domain registration](../../README.md#code-review-domain)
