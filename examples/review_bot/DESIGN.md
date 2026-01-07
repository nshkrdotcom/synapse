# ReviewBot Design Document

## Overview

ReviewBot is a Phoenix LiveView application demonstrating Synapse's multi-agent orchestration framework with real-time streaming, workflow persistence, and database integration.

## Architecture

### Technology Stack

- **Phoenix 1.7.14**: Web framework with LiveView for real-time UI
- **Synapse**: Multi-agent workflow orchestration
- **Jido**: Action execution framework
- **Ecto + PostgreSQL**: Database persistence
- **PubSub**: Real-time messaging between workflow and UI

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Phoenix LiveView UI                       │
│  (Real-time updates via PubSub subscriptions)               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Reviews Context (Business Logic)                │
│  - Review Schema & Changesets                               │
│  - CRUD Operations                                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│         Synapse Workflow Engine (Multi-Provider)            │
│  - Parallel execution of provider steps                     │
│  - Dependency resolution                                     │
│  - Automatic persistence to Postgres                         │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼             ▼
   ┌────────┐  ┌─────────┐  ┌─────────┐
   │ Claude │  │  Codex  │  │ Gemini  │
   │ Action │  │ Action  │  │ Action  │
   └────┬───┘  └────┬────┘  └────┬────┘
        │           │             │
        └───────────┼─────────────┘
                    ▼
        ┌────────────────────────┐
        │ Aggregate Reviews      │
        │ Action                 │
        └────────────────────────┘
```

## Key Design Patterns

### 1. Phoenix + Synapse Integration

**Pattern**: Async workflow execution with PubSub broadcasting

```elixir
# In LiveView
def mount(%{"id" => id}, _session, socket) do
  review = Reviews.get_review!(id)

  if connected?(socket) do
    Phoenix.PubSub.subscribe(ReviewBot.PubSub, "review:#{id}")
  end

  {:ok, assign(socket, review: review, provider_results: %{})}
end

# In Jido Action
def run(params, context) do
  result = provider.review_code(code, language)

  # Broadcast to LiveView subscribers
  Phoenix.PubSub.broadcast(
    ReviewBot.PubSub,
    "review:#{context[:review_id]}",
    {:provider_result, provider, result}
  )

  result
end
```

**Benefits**:
- Real-time UI updates without polling
- Decoupled workflow execution from presentation
- Scalable to multiple concurrent reviews

### 2. Synapse Workflow Persistence

**Pattern**: Automatic state snapshots to Postgres

```elixir
Engine.execute(spec,
  input: %{code: review.code, language: review.language},
  context: %{request_id: review.workflow_id, review_id: review.id},
  persistence: {Postgres, repo: ReviewBot.Repo}
)
```

**Benefits**:
- Automatic workflow state tracking
- Crash recovery capabilities
- Audit trail for debugging
- Request ID based workflow identification

### 3. Dynamic Step Generation

**Pattern**: Build workflow steps programmatically based on providers

```elixir
provider_steps = Enum.map(providers, fn provider ->
  [
    id: :"#{provider}_review",
    action: ReviewCode,
    params: %{code: code, provider: provider},
    on_error: :continue,
    retry: [max_attempts: 2, backoff: 500]
  ]
end)
```

**Benefits**:
- Flexible provider selection
- Easy to add/remove providers
- Individual error handling per provider

### 4. Context-Based Communication

**Pattern**: Pass metadata through workflow context

```elixir
context: %{
  request_id: review.workflow_id,
  review_id: review.id
}

# Available in all actions
def run(params, context) do
  review_id = context[:review_id]
  # Use for PubSub broadcasting, logging, etc.
end
```

**Benefits**:
- Consistent metadata across all steps
- Easy debugging and tracing
- Enables cross-cutting concerns (logging, metrics, etc.)

### 5. Provider Abstraction

**Pattern**: Behaviour-based provider interface

```elixir
@callback available?() :: boolean()
@callback review_code(code :: String.t(), language :: String.t() | nil) ::
            {:ok, map()} | {:error, term()}
```

**Benefits**:
- Easy to swap real providers with mocks
- Consistent interface across all providers
- Testability without API keys

## Data Flow

### Creating a Review

1. User submits code via `ReviewLive.New`
2. `Reviews.create_review/1` creates database record with workflow_id
3. `MultiProviderReview.run_async/1` starts workflow in background
4. LiveView redirects to show page
5. Show page subscribes to PubSub for updates

### Workflow Execution

1. **Engine Start**: Synapse creates initial snapshot (status: pending)
2. **Parallel Execution**: All provider steps run concurrently
3. **Step Completion**: Each action broadcasts result via PubSub
4. **LiveView Update**: Client receives and renders each provider result
5. **Aggregation**: Final step combines results
6. **Completion**: Engine saves final snapshot (status: completed)

### Real-time Updates

```
Workflow Action → PubSub.broadcast → Phoenix.PubSub
                                           ↓
                                    LiveView.handle_info
                                           ↓
                                    Update assigns
                                           ↓
                                    Re-render (via LiveView)
```

## Database Schema

### Reviews Table

```sql
CREATE TABLE reviews (
  id SERIAL PRIMARY KEY,
  code TEXT NOT NULL,
  language VARCHAR(255),
  status VARCHAR(255) DEFAULT 'pending' NOT NULL,
  results JSONB DEFAULT '{}',
  workflow_id VARCHAR(255),
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### Workflow Executions Table (Synapse)

Automatically created by Synapse for persistence:

```sql
CREATE TABLE workflow_executions (
  id SERIAL PRIMARY KEY,
  request_id VARCHAR(255) UNIQUE NOT NULL,
  spec_name VARCHAR(255) NOT NULL,
  spec_version INTEGER NOT NULL,
  status VARCHAR(255) NOT NULL,
  input JSONB NOT NULL,
  context JSONB NOT NULL,
  results JSONB NOT NULL,
  audit_trail JSONB NOT NULL,
  last_step_id VARCHAR(255),
  last_attempt INTEGER,
  error JSONB,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

## Error Handling

### Provider-Level Errors

- Each provider step has `on_error: :continue`
- Failed providers don't block aggregation
- Aggregation works with partial results

### Workflow-Level Errors

- Synapse captures errors in audit trail
- Failed workflows update review status to `:failed`
- UI shows retry button for failed reviews

### Example Error Flow

```
Provider Step Fails
    ↓
Synapse retries (max_attempts: 2)
    ↓
Still fails → on_error: :continue
    ↓
Step marked as error in results
    ↓
Workflow continues with remaining providers
    ↓
Aggregation receives partial results
    ↓
UI shows which providers succeeded/failed
```

## Performance Considerations

### Parallel Provider Execution

Synapse automatically parallelizes independent steps:
- All 3 providers execute simultaneously
- Total time ≈ slowest provider (not sum of all)
- Estimated: 1-2 seconds vs 3-6 seconds sequential

### Database Optimization

- Index on `status` for filtering
- Index on `workflow_id` for lookups
- Index on `inserted_at` for ordering
- JSONB for flexible results storage

### LiveView Optimizations

- Only subscribe to PubSub when connected
- Incremental updates (only changed provider results)
- CSS loaded once, updates via WebSocket

## Testing Strategy

### Unit Tests

- Review context CRUD operations
- Provider mock implementations
- Action parameter validation

### Integration Tests

- LiveView navigation and rendering
- Form submission and validation
- Real-time update reception

### Test Fixtures

```elixir
def review_fixture(attrs \\ %{}) do
  {:ok, review} =
    attrs
    |> Enum.into(%{
      code: "defmodule Example do\n  def hello, do: :world\nend",
      language: "elixir",
      status: :pending
    })
    |> Reviews.create_review()

  review
end
```

## Future Enhancements

1. **Authentication**: Add user accounts and review ownership
2. **Real Providers**: Integrate actual AI APIs (Claude, Codex, Gemini)
3. **Code Diff**: Support reviewing changes, not just full code
4. **Team Features**: Share reviews, comments, discussions
5. **Metrics Dashboard**: Aggregate quality scores over time
6. **Webhook Integration**: Trigger reviews from GitHub PRs
7. **Custom Rules**: Allow users to define review criteria
8. **Export Reports**: Generate PDF/HTML review reports

## Deployment Considerations

### Environment Variables

```bash
DATABASE_URL=ecto://user:pass@localhost/review_bot_prod
SECRET_KEY_BASE=$(mix phx.gen.secret)
PHX_HOST=reviewbot.example.com
PORT=4000

# Optional: Real provider API keys
ANTHROPIC_API_KEY=sk-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
```

### Production Checklist

- [ ] Run database migrations
- [ ] Configure SECRET_KEY_BASE
- [ ] Set up SSL certificates
- [ ] Configure production database
- [ ] Enable release mode
- [ ] Set up monitoring (telemetry)
- [ ] Configure log aggregation
- [ ] Set up backup strategy

## Conclusion

ReviewBot demonstrates how Synapse's workflow orchestration integrates seamlessly with Phoenix LiveView to create responsive, real-time applications. The combination of declarative workflows, automatic persistence, and PubSub-based updates provides a robust foundation for multi-agent systems.
