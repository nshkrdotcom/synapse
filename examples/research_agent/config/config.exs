import Config

config :research_agent,
  default_provider: :gemini,
  max_sources: 10,
  reliability_threshold: 0.6

# Synapse workflow persistence
config :synapse, Synapse.Workflow.Engine,
  # Disable persistence for example app by default
  persistence: nil

# Import environment specific config
import_config "#{config_env()}.exs"
