import Config

# Configure the endpoint
config :review_bot, ReviewBotWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ReviewBotWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: ReviewBot.PubSub,
  live_view: [signing_salt: "review_bot_secret"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  review_bot: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (optional, using simple CSS instead)
config :tailwind, version: "3.4.3", review_bot: []

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure the database
config :review_bot,
  ecto_repos: [ReviewBot.Repo]

# Configure Synapse workflow persistence
config :synapse, Synapse.Workflow.Engine,
  persistence: {Synapse.Workflow.Persistence.Postgres, repo: ReviewBot.Repo}

# Import environment specific config
import_config "#{config_env()}.exs"
