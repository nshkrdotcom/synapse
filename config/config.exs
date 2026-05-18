# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :synapse_core, Synapse.Config,
  tenant_id: "default",
  product_slug: "nshkr-agent",
  product_name: "NSHKR Agent",
  product_family: "agent_workspace",
  pack_version: "0.1.0",
  default_installation_id: "default",
  bootstrap_mode: :disabled,
  execution_timeout_ms: 300_000,
  operator_surface_enabled?: true

config :synapse_web,
  generators: [context_app: :synapse_core]

# Configures the endpoint
config :synapse_web, SynapseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SynapseWeb.ErrorHTML, json: SynapseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Synapse.PubSub,
  live_view: [signing_salt: "ipZlJU+z"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  synapse_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/synapse_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  synapse_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/synapse_web", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
