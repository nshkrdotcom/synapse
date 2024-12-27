defmodule Axon.AgentSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
      # {Axon.Agent.Server,
      #   name: :example_agent,
      #   python_module: "agents.example_agent",
      #   model: "default",
      #   port: 8000,
      #   extra_env: [{"PYTHONPATH", python_path}]
      # },
    python_path = Path.join(File.cwd!(), "apps/axon_python/src")
    config = [
      name: :example_agent,
      python_module: "agents.example_agent",
      model: "default",
      port: 8000,
      extra_env: [{"PYTHONPATH", python_path}]

      # id: "agent_1",
      # script: "agent.py",
      # env: [{"SOME_ENV", "value"}]
    ]

    # config = %{
    #   id: "agent_1",
    #   script: "agent.py",
    #   env: [{"SOME_ENV", "value"}]
    # }
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    start_agent(config)
  end

  @impl true
  def init(_init_arg) do
      # {Axon.Agent.Server,
      #   name: :example_agent,
      #   python_module: "agents.example_agent",
      #   model: "default",
      #   port: 8000,
      #   extra_env: [{"PYTHONPATH", python_path}]
      # },


    DynamicSupervisor.init(max_restarts: 2, max_children: 42, strategy: :one_for_one)
  end

  @doc """
  Starts a new agent with the given configuration
  """
  def start_agent(config) do
    child_spec = %{
      id: Axon.Agent.Server,
      start: {Axon.Agent.Server, :start_link, [config]},
      restart: :permanent,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stops an agent by its ID
  """
  def stop_agent(agent_id) do
    case Registry.lookup(Axon.AgentRegistry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
