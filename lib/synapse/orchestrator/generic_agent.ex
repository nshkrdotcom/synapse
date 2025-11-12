defmodule Synapse.Orchestrator.GenericAgent do
  @moduledoc """
  Minimal Jido agent used by the orchestrator to execute runtime-configured
  actions. All configurable behavior is injected via the orchestrator rather
  than compile-time options.
  """

  # Suppress Dialyzer warnings for callback spec mismatches in Jido.Agent
  # These arise because Jido.Agent's @callback definitions expect Jido.Agent.t()
  # but the actual implementations work with Jido.Agent.Server.State.t()
  @dialyzer [
    {:nowarn_function, mount: 2},
    {:nowarn_function, shutdown: 2},
    {:nowarn_function, do_validate: 3},
    {:nowarn_function, pending?: 1},
    {:nowarn_function, reset: 1}
  ]

  use Jido.Agent,
    name: "synapse_generic",
    description: "Runtime configurable agent managed by Synapse Orchestrator",
    category: "synapse/orchestrator",
    tags: ["orchestrator", "dynamic"],
    schema: [
      data: [type: :map, default: %{}],
      metadata: [type: :map, default: %{}]
    ]
end
