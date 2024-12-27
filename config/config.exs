import Config

config :grpc,
  start_server: true,
  services: [
    AxonCore.AgentGrpcServer
  ]

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
  python_module_path: "apps/axon_python/src"

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
