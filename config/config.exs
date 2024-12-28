import Config

# config :grpc,
#   start_server: true,
#   services: [
#     AxonCore.AgentGrpcServer
#   ]

config :axon,
  # Add any necessary configuration here for your application
  # For example, you can define the default port for your Phoenix application
  http: [port: 4000]

# Configure Finch
config :axon_core, :finch,
  name: AxonFinch,
  pools: %{
    :default => [size: 10]
  }

# ... other configurations ...

config :axon_core,
  python_min_version: "3.10.0",
  python_max_version: "3.13.0",
  python_venv_path: ".venv",
  python_requirements_path: "requirements.txt",
  python_module_path: "apps/axon_python/src",
  python_env: %{
    # Path to the Python executable, using the virtual environment's Python
    python_path: Path.join([System.get_env("HOME"), ".cache", "axon", ".venv", "bin", "python"])
  }

# General application configuration
# config :logger,
# level: :debug,
# backends: [:console],
# format: "$time $metadata[$level] $message\n",
# metadata: [:request_id]


config :logger,
  level: :debug,
  truncate: :infinity,
  format: "$time $metadata[$level] $message\n",
  metadata: [request_id: nil, trace_id: nil],
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [request_id: nil, trace_id: nil]


# Finch configuration
config :finch,
# Define a default pool for HTTP connections
default_pool: [size: 10]
