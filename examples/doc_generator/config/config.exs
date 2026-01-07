import Config

config :doc_generator,
  default_style: :formal

# Synapse workflow persistence
config :synapse, Synapse.Workflow.Engine,
  # Disable persistence for example app by default
  persistence: nil

# Import environment specific config
import_config "#{config_env()}.exs"
