import Config

# Import the base configuration from config.exs
import_config "config.exs"

# Override config values for the development environment

# Show more detailed logging in development
config :logger, level: :debug

# Configure the console backend to show all metadata
config :logger, :console,
  metadata: [:request_id, :trace_id]

# If you are using Phoenix, you may want to enable code reloading
# and other development-specific settings
#
# config :phoenix, :live_reload, [:code, :assets, :html]
# config :phoenix, :logger, level: :debug
