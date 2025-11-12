# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :synapse,
  ecto_repos: [Synapse.Repo],
  generators: [timestamp_type: :utc_datetime]

config :synapse, Synapse.Workflow.Engine, persistence: {Synapse.Workflow.Persistence.Postgres, []}

config :synapse, Synapse.Orchestrator.Runtime,
  enabled: config_env() != :test,
  config_source: {:priv, "orchestrator_agents.exs"},
  include_types: :all,
  reconcile_interval: 1_000

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
