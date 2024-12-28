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


    DynamicSupervisor.init(max_restarts: 1, max_children: 42, strategy: :one_for_one)
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




# defmodule MultiAgent.AgentSupervisor do
#   use DynamicSupervisor

#   def start_link(init_arg) do
#     DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
#   end

#   @impl true
#   def init(_init_arg) do
#     DynamicSupervisor.init(strategy: :one_for_one)
#   end

#   @doc """
#   Starts a new agent with the given configuration
#   """
#   def start_agent(config) do
#     child_spec = %{
#       id: MultiAgent.Agent,
#       start: {MultiAgent.Agent, :start_link, [config]},
#       restart: :permanent,
#       type: :worker
#     }

#     DynamicSupervisor.start_child(__MODULE__, child_spec)
#   end

#   @doc """
#   Stops an agent by its ID
#   """
#   def stop_agent(agent_id) do
#     case Registry.lookup(MultiAgent.AgentRegistry, agent_id) do
#       [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
#       [] -> {:error, :not_found}
#     end
#   end
# end



# ```

# This supervision tree architecture has several key features:

# 1. **Top-level Application Supervisor**
#    - Uses `:one_for_one` strategy
#    - Manages the Registry and AgentSupervisor
#    - If the Registry crashes, only it restarts
#    - If the AgentSupervisor crashes, only it and its children restart

# 2. **Dynamic Supervisor for Agents**
#    - Allows dynamically starting and stopping agents
#    - Each agent failure is isolated
#    - Uses `:one_for_one` strategy so agent crashes don't affect siblings

# 3. **Agent Process**
#    - Manages a single Python process
#    - Handles port communication
#    - Registered in Registry for easy lookup
#    - Can be restarted independently

# To use this framework:

# ```elixir
# # Start a new agent
# config = %{
#   id: "agent_1",
#   script: "agent.py",
#   env: [{"SOME_ENV", "value"}]
# }
# MultiAgent.AgentSupervisor.start_agent(config)

# # Send a message to an agent
# MultiAgent.Agent.send_message("agent_1", "hello")

# # Stop an agent
# MultiAgent.AgentSupervisor.stop_agent("agent_1")
# ```

# Key benefits of this architecture:

# 1. **Isolation**: Each agent runs in its own process with its own Python subprocess
# 2. **Dynamic**: Agents can be started and stopped at runtime
# 3. **Fault Tolerant**: Individual agent crashes don't affect other agents
# 4. **Discoverable**: Agents are registered and can be looked up by ID
# 5. **Maintainable**: Clear separation of concerns between supervision and agent logic

# You might want to add:

# 1. Agent state persistence
# 2. Agent communication patterns
# 3. Resource limits (max agents)
# 4. Agent health monitoring
# 5. Configuration validation
# 6. Message queuing

# Would you like me to elaborate on any of these aspects or modify the implementation in any way?
