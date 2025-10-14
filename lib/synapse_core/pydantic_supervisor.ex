defmodule SynapseCore.PydanticSupervisor do
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Ensure Python environment is ready before starting services
    :ok = SynapseCore.PythonEnvManager.ensure_env!()

    children = [
      {SynapseCore.PydanticHTTPClient, []},
      {SynapseCore.PydanticToolRegistry, []},
      {DynamicSupervisor, strategy: :one_for_one, name: SynapseCore.AgentSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_agent(config) do
    DynamicSupervisor.start_child(
      SynapseCore.AgentSupervisor,
      {SynapseCore.PydanticAgentProcess,
       Map.put(config, :env_vars, SynapseCore.PythonEnvManager.env_vars())}
    )
  end

  def stop_agent(name) do
    case Process.whereis(String.to_atom(name)) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(SynapseCore.AgentSupervisor, pid)
    end
  end

  def list_agents do
    DynamicSupervisor.which_children(SynapseCore.AgentSupervisor)
  end

  def status do
    %{
      http_client: Process.whereis(SynapseCore.PydanticHTTPClient) != nil,
      tool_registry: Process.whereis(SynapseCore.PydanticToolRegistry) != nil,
      agent_supervisor: Process.whereis(SynapseCore.AgentSupervisor) != nil,
      python_env: %{
        path: SynapseCore.PythonEnvManager.python_path(),
        env_vars: SynapseCore.PythonEnvManager.env_vars()
      }
    }
  end
end
