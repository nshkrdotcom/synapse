# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# jido and jido_signal both define Jido.Signal.TraceContext; ignore redefinition warnings.
Code.compiler_options(ignore_module_conflict: true)

config :synapse,
  ecto_repos: [Synapse.Repo],
  generators: [timestamp_type: :utc_datetime]

config :synapse, Synapse.Workflow.Engine, persistence: {Synapse.Workflow.Persistence.Postgres, []}

config :synapse, Synapse.Orchestrator.Runtime,
  enabled: config_env() != :test,
  config_source: {:priv, "orchestrator_agents.exs"},
  include_types: :all,
  reconcile_interval: 1_000

# Signal Registry Configuration
config :synapse, Synapse.Signal.Registry,
  topics: [
    task_request: [
      type: "synapse.task.request",
      schema: [
        task_id: [type: :string, required: true, doc: "Unique task identifier"],
        payload: [type: :map, default: %{}, doc: "Task-specific payload data"],
        metadata: [type: :map, default: %{}, doc: "Arbitrary metadata"],
        labels: [type: {:list, :string}, default: [], doc: "Labels for routing/filtering"],
        priority: [
          type: {:in, [:low, :normal, :high, :urgent]},
          default: :normal,
          doc: "Task priority"
        ]
      ]
    ],
    task_result: [
      type: "synapse.task.result",
      schema: [
        task_id: [type: :string, required: true, doc: "Task identifier this result belongs to"],
        agent: [type: :string, required: true, doc: "Agent/worker that produced this result"],
        status: [type: {:in, [:ok, :error, :partial]}, default: :ok, doc: "Result status"],
        output: [type: :map, default: %{}, doc: "Result output data"],
        metadata: [type: :map, default: %{}, doc: "Execution metadata"]
      ]
    ],
    task_summary: [
      type: "synapse.task.summary",
      schema: [
        task_id: [type: :string, required: true, doc: "Task identifier"],
        status: [type: :atom, default: :complete, doc: "Overall task status"],
        results: [type: {:list, :map}, default: [], doc: "Aggregated results"],
        metadata: [type: :map, default: %{}, doc: "Summary metadata"]
      ]
    ],
    worker_ready: [
      type: "synapse.worker.ready",
      schema: [
        worker_id: [type: :string, required: true, doc: "Worker identifier"],
        capabilities: [type: {:list, :string}, default: [], doc: "Worker capabilities"]
      ]
    ]
  ]

# Auto-register domains on startup (for backward compatibility)
config :synapse, :domains, [Synapse.Domains.CodeReview]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :agent_id,
    :reason,
    :router,
    :config,
    :topic,
    :workflow,
    :status,
    :config_id,
    :review_id,
    :severity,
    :decision_path,
    :duration_ms,
    :finding_count,
    :recommendation_count,
    :specialists,
    :escalation_count,
    :negotiation_count,
    :module,
    :pid,
    :profile,
    :error_type,
    :error_message,
    :type,
    :path,
    :summary,
    :failed_step,
    :findings_count,
    :confidence,
    :files,
    :language,
    :tokens,
    :prompt_length,
    :rationale,
    :error
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
