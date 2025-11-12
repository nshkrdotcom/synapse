defmodule Synapse.Orchestrator.Runtime.State do
  @moduledoc false

  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.Orchestrator.Runtime.RunningAgent

  @type agent_id :: AgentConfig.agent_id()

  @type t :: %__MODULE__{
          config_source: String.t() | module(),
          agent_configs: [AgentConfig.t()],
          running_agents: %{optional(agent_id()) => RunningAgent.t()},
          monitors: %{optional(reference()) => agent_id()},
          router: atom() | nil,
          registry: atom() | nil,
          include_types: :all | [AgentConfig.agent_type()],
          reconcile_interval: pos_integer(),
          last_reconcile: DateTime.t() | nil,
          reconcile_count: non_neg_integer(),
          metadata: map(),
          skill_registry: pid() | nil,
          skills_summary: String.t()
        }

  defstruct [
    :config_source,
    agent_configs: [],
    running_agents: %{},
    monitors: %{},
    router: nil,
    registry: nil,
    include_types: :all,
    reconcile_interval: 5_000,
    last_reconcile: nil,
    reconcile_count: 0,
    metadata: %{},
    skill_registry: nil,
    skills_summary: ""
  ]
end
