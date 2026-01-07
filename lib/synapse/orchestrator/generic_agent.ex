defmodule Synapse.Orchestrator.GenericAgent do
  @moduledoc """
  Minimal Jido agent used by the orchestrator to execute runtime-configured
  actions. All configurable behavior is injected via the orchestrator rather
  than compile-time options.
  """

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
