# ReviewBot

A Phoenix LiveView application demonstrating Synapse multi-agent orchestration with real-time streaming code reviews.

## Features

- **Multi-Provider Reviews**: Get code reviews from Claude, Codex, and Gemini simultaneously
- **Real-Time Streaming**: See results appear as each AI provider completes
- **Workflow Persistence**: All workflow states automatically saved to PostgreSQL
- **Review History**: Browse and filter past code reviews
- **Responsive UI**: Clean, modern interface with live updates

## Architecture

ReviewBot showcases the integration between:

- **Synapse**: Multi-agent workflow orchestration framework
- **Jido**: Action execution with schema validation
- **Phoenix LiveView**: Real-time web interface
- **Ecto + PostgreSQL**: Database persistence and migrations
- **PubSub**: Real-time messaging between backend and UI

## Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)

## Quick Start

### 1. Install Dependencies

```bash
cd examples/review_bot
mix deps.get
cd assets && npm install && cd ..
```

### 2. Setup Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate
```

### 3. Start the Server

```bash
mix phx.server
```

Or start interactively:

```bash
iex -S mix phx.server
```

### 4. Open Your Browser

Visit [http://localhost:4000](http://localhost:4000)

## Usage

### Submit a Code Review

1. Click "New Review" in the navigation
2. Paste your code in the text area
3. Optionally specify the programming language
4. Click "Submit for Review"

### Watch Results Stream In

- You'll be redirected to the review page
- Each provider's results appear as they complete
- See individual analyses from Claude, Codex, and Gemini
- View aggregated summary with overall quality score

### Browse Review History

- Navigate to the home page to see all reviews
- Filter by status: Pending, In Progress, Completed, Failed
- Click any review to see full details

## Project Structure

```
review_bot/
├── lib/
│   ├── review_bot/
│   │   ├── application.ex          # OTP application
│   │   ├── repo.ex                 # Ecto repository
│   │   ├── reviews/                # Business logic context
│   │   │   ├── review.ex           # Review schema
│   │   │   └── reviews.ex          # CRUD operations
│   │   ├── providers/              # AI provider implementations
│   │   │   ├── behaviour.ex        # Provider contract
│   │   │   ├── claude.ex           # Claude mock provider
│   │   │   ├── codex.ex            # Codex mock provider
│   │   │   └── gemini.ex           # Gemini mock provider
│   │   ├── actions/                # Jido actions
│   │   │   ├── review_code.ex      # Single provider review
│   │   │   └── aggregate_reviews.ex # Combine results
│   │   └── workflows/              # Synapse workflows
│   │       └── multi_provider_review.ex
│   └── review_bot_web/             # Phoenix web layer
│       ├── components/             # UI components
│       ├── live/                   # LiveView modules
│       │   └── review_live/
│       │       ├── index.ex        # Review list
│       │       ├── new.ex          # Submit new review
│       │       └── show.ex         # View review results
│       ├── endpoint.ex             # Phoenix endpoint
│       └── router.ex               # Route definitions
├── priv/
│   └── repo/
│       └── migrations/             # Database migrations
├── test/                           # Test suite
├── assets/                         # Frontend assets
│   ├── css/
│   │   └── app.css                 # Application styles
│   └── js/
│       └── app.js                  # LiveView client
├── config/                         # Configuration files
├── DESIGN.md                       # Architecture documentation
└── README.md                       # This file
```

## Configuration

### Database

Edit `config/dev.exs`:

```elixir
config :review_bot, ReviewBot.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "review_bot_dev",
  pool_size: 10
```

### Synapse Persistence

Configured in `config/config.exs`:

```elixir
config :synapse, Synapse.Workflow.Engine,
  persistence: {Synapse.Workflow.Persistence.Postgres, repo: ReviewBot.Repo}
```

## Testing

Run the full test suite:

```bash
mix test
```

Run tests with coverage:

```bash
mix test --cover
```

Run specific test file:

```bash
mix test test/review_bot/reviews_test.exs
```

## How It Works

### 1. Workflow Orchestration

When you submit code for review, Synapse creates a workflow with:

- 3 parallel provider steps (Claude, Codex, Gemini)
- 1 aggregation step (depends on all providers)
- Automatic retry on failure (max 2 attempts)
- Error handling (failed providers don't block aggregation)

### 2. Real-Time Updates

```elixir
# Action broadcasts results
Phoenix.PubSub.broadcast(
  ReviewBot.PubSub,
  "review:#{review_id}",
  {:provider_result, :claude, result}
)

# LiveView receives updates
def handle_info({:provider_result, provider, result}, socket) do
  # Update UI in real-time
end
```

### 3. Workflow Persistence

Every workflow state is automatically saved to PostgreSQL:

- Pending: Initial state
- Running: Steps executing
- Completed: All steps finished
- Failed: Unrecoverable error

You can inspect workflow state in the database:

```sql
SELECT * FROM workflow_executions WHERE request_id = 'review_...';
```

## Development

### Reset Database

```bash
mix ecto.reset
```

### Generate Migration

```bash
mix ecto.gen.migration add_some_field
```

### Interactive Console

```bash
iex -S mix

# Try it out
iex> {:ok, review} = ReviewBot.Reviews.create_review(%{code: "def test, do: :ok"})
iex> ReviewBot.Workflows.MultiProviderReview.run(review)
```

## Extending ReviewBot

### Add a New Provider

1. Create provider module:

```elixir
defmodule ReviewBot.Providers.NewProvider do
  @behaviour ReviewBot.Providers.Behaviour

  @impl true
  def available?, do: true

  @impl true
  def review_code(code, language) do
    # Your implementation
  end
end
```

2. Update workflow to include new provider:

```elixir
@default_providers [:claude, :codex, :gemini, :new_provider]
```

### Add Real AI Integration

Replace mock providers with actual API calls:

```elixir
defmodule ReviewBot.Providers.Claude do
  @impl true
  def review_code(code, language) do
    # Call Anthropic Claude API
    ClaudeAgentSDK.generate(%{
      model: "claude-opus-4",
      messages: [%{role: "user", content: build_prompt(code, language)}]
    })
  end
end
```

## Production Deployment

### 1. Build Release

```bash
MIX_ENV=prod mix release
```

### 2. Set Environment Variables

```bash
export DATABASE_URL="ecto://user:pass@localhost/review_bot_prod"
export SECRET_KEY_BASE="..."
export PHX_HOST="reviewbot.example.com"
```

### 3. Run Migrations

```bash
_build/prod/rel/review_bot/bin/review_bot eval "ReviewBot.Release.migrate"
```

### 4. Start Server

```bash
_build/prod/rel/review_bot/bin/review_bot start
```

## Troubleshooting

### Database Connection Error

```bash
# Check PostgreSQL is running
pg_isready

# Verify credentials in config/dev.exs
```

### Assets Not Loading

```bash
# Rebuild assets
cd assets && npm install && cd ..
mix assets.deploy
```

### LiveView Not Connecting

- Check browser console for WebSocket errors
- Verify `config/dev.exs` has correct host settings
- Ensure `mix phx.server` is running (not just `mix run`)

## Learn More

- **Synapse Documentation**: [Main README](../../README.md)
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view
- **Jido Actions**: https://hexdocs.pm/jido
- **Design Document**: [DESIGN.md](DESIGN.md)

## Contributing

This is an example application demonstrating Synapse capabilities. Feel free to:

- Report issues
- Suggest improvements
- Create pull requests
- Use as a template for your own projects

## License

MIT License - see main Synapse repository for details.
