import Config

# Configure logging
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :workflow, :step]

# Import environment-specific config
import_config "#{config_env()}.exs"
