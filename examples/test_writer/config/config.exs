import Config

config :test_writer,
  max_fix_attempts: 3,
  compile_timeout: 30_000,
  test_timeout: 60_000

# Synapse workflow persistence
config :synapse, Synapse.Workflow.Engine,
  # Disable persistence for example app by default
  persistence: nil

# Import environment specific config
import_config "#{config_env()}.exs"
