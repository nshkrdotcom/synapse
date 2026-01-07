import Config

config :coding_agent,
  default_provider: :claude

# Synapse workflow persistence
config :synapse, Synapse.Workflow.Engine,
  # Disable persistence for example app by default
  persistence: nil

# Import environment specific config
import_config "#{config_env()}.exs"
