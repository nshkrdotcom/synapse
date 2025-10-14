defmodule SynapseCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # python_path = Path.join(File.cwd!(), "scripts/src")
    children = [
      # Start the Registry for agent processes
      {Registry, keys: :unique, name: SynapseCore.AgentRegistry},
      # Start the Telemetry supervisor
      # SynapseCore.Telemetry,
      # Start the PubSub system
      # {Phoenix.PubSub, name: SynapseCore.PubSub},
      # Start a single test agent
      # {SynapseCore.Agent.Server,
      #   name: :example_agent,
      #   python_module: "agents.example_agent",
      #   model: "default",
      #   port: 8000,
      #   extra_env: [{"PYTHONPATH", python_path}]
      # },
      # %{
      #   id: SynapseCore.Agent.Server,
      #   start: {SynapseCore.Agent.Server, :start_link, [
      #     name: :example_agent,
      #     python_module: "agents.example_agent",
      #     model: "default",
      #     port: 8000,
      #     extra_env: [{"PYTHONPATH", python_path},
      #   ]]},
      #   restart: :permanent, # Or :permanent if you want it always restarted, :permanent, :temporary, :transient
      #   shutdown: 50000,
      #   type: :worker
      # },
      SynapseCore.AgentSupervisor
      # %{
      #   id: SynapseCore.Agent.Server,
      #   start: {SynapseCore.Agent.Server, :start_link, [
      #     [
      #       name: :example_agent,
      #       python_module: "agents.example_agent",
      #       model: "default",
      #       port: 8000,
      #       extra_env: [{"PYTHONPATH", python_path}]
      #     ]
      #   ]},
      #   restart: :permanent,
      #   shutdown: 50000,
      #   type: :supervisor
      # },
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    # , max_restarts: 1, max_seconds: 30]
    opts = [strategy: :one_for_one, name: SynapseCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# defmodule MultiAgent.Application do
#   use Application

#   @impl true
#   def start(_type, _args) do
#     children = [
#       # Registry for naming agents
#       {Registry, keys: :unique, name: MultiAgent.AgentRegistry},

#       # Dynamic supervisor for managing agent processes
#       MultiAgent.AgentSupervisor
#     ]

#     opts = [strategy: :one_for_one, name: MultiAgent.Supervisor]
#     Supervisor.start_link(children, opts)
#   end
