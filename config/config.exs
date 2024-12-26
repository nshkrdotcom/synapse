import Config

config :grpc,
  start_server: true,
  services: [
    AxonCore.AgentGrpcServer
  ]

# ... other configurations ...

config :axon_core,
  python_min_version: "3.10.0",
  python_max_version: "3.13.0",
  python_venv_path: ".venv",
  python_requirements_path: "requirements.txt",
  python_module_path: "apps/axon_python/src"

config :logger,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id],
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id]
