import Config

# Configure your database
config :review_bot, ReviewBot.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "review_bot_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :review_bot, ReviewBotWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "development_secret_key_base_at_least_64_bytes_long_for_security_purposes_in_production",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:review_bot, ~w(--sourcemap=inline --watch)]}
  ]

# Watch static and templates for browser reloading.
config :review_bot, ReviewBotWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/review_bot_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
