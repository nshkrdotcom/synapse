import Config

# Development repository configuration
config :synapse, Synapse.Repo,
  database: System.get_env("POSTGRES_DB", "synapse_dev"),
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  show_sensitive_data_on_connection_error: true,
  pool_size: String.to_integer(System.get_env("POSTGRES_POOL_SIZE", "10"))

# Verbose logging in development
config :logger, :default_formatter, format: "[$level] $message\n"
