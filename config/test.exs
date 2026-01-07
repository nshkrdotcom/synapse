import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :synapse, Synapse.Repo,
  database: System.get_env("POSTGRES_DB_TEST", "synapse_test"),
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :synapse, Synapse.Workflow.Engine, persistence: nil

config :synapse, :suppress_reqllm_warnings, true
