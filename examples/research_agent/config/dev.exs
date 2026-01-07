import Config

# Development configuration
config :research_agent,
  log_level: :debug

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
