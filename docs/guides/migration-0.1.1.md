# Migration Guide: v0.1.0 to v0.1.1

This guide covers migrating from Synapse v0.1.0 (code-review-specific) to
v0.1.1 (domain-agnostic).

## Overview of Changes

### Signal Layer

**Before (v0.1.0):**
- Hardcoded signal topics: `:review_request`, `:review_result`, `:review_summary`
- Signal schemas defined as modules in `lib/synapse/signal/`

**After (v0.1.1):**
- Dynamic signal registry with config-based or runtime registration
- Generic core signals: `:task_request`, `:task_result`, `:task_summary`
- Code review signals available via `Synapse.Domains.CodeReview`

### Agent Configuration

**Before:**
```elixir
signals: %{
  subscribes: [:review_request],
  emits: [:review_result]
}
```

**After:**
```elixir
signals: %{
  subscribes: [:review_request],
  emits: [:review_result],
  roles: %{
    request: :review_request,
    result: :review_result,
    summary: :review_summary
  }
}
```

### Action Locations

**Before:**
- `Synapse.Actions.Review.ClassifyChange`
- `Synapse.Actions.Security.CheckSQLInjection`

**After:**
- `Synapse.Domains.CodeReview.Actions.ClassifyChange`
- `Synapse.Domains.CodeReview.Actions.CheckSQLInjection`

(Old locations still work but are deprecated)

## Migration Steps

### Step 1: Register Code Review Domain

If you're using code review signals, explicitly register the domain:

```elixir
# application.ex
def start(_type, _args) do
  # Register code review domain
  Synapse.Domains.CodeReview.register()

  children = [
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Or via config (recommended):

```elixir
# config/config.exs
config :synapse, :domains, [Synapse.Domains.CodeReview]
```

### Step 2: Update Action References (Optional)

Update action module references to new locations:

```elixir
# Before
alias Synapse.Actions.Security.CheckSQLInjection

# After
alias Synapse.Domains.CodeReview.Actions.CheckSQLInjection
```

The old locations work but emit deprecation warnings.

### Step 3: Add Signal Roles (Recommended)

For orchestrator agents, explicitly define signal roles:

```elixir
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
```

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
- `:specialist_ready` signal schema changed:
  - Old: `{agent, router, timestamp, context}`
  - New: `{specialist_id, capabilities}`

### Deprecated

- `Synapse.Actions.Review.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Security.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Performance.*` (use `Synapse.Domains.CodeReview.Actions.*`)

## Compatibility Mode

For gradual migration, enable legacy signal support:

```elixir
# config/config.exs
config :synapse, :domains, [Synapse.Domains.CodeReview]
```

This registers the review signals automatically, maintaining v0.1.0 behavior.

## Getting Help

- [Custom Domains Guide](./custom-domains.md)
- [GitHub Issues](https://github.com/your-org/synapse/issues)
