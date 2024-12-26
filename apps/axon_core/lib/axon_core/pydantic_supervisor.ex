defmodule AxonCore.PydanticSupervisor do
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Ensure Python environment is ready before starting services
    :ok = AxonCore.PythonEnvManager.ensure_env!()

    children = [
      {AxonCore.PydanticHTTPClient, []},
      {AxonCore.PydanticToolRegistry, []},
      {DynamicSupervisor, strategy: :one_for_one, name: AxonCore.AgentSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_agent(config) do
    DynamicSupervisor.start_child(
      AxonCore.AgentSupervisor,
      {AxonCore.PydanticAgentProcess, Map.put(config, :env_vars, AxonCore.PythonEnvManager.env_vars())}
    )
  end

  def stop_agent(name) do
    case Process.whereis(String.to_atom(name)) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(AxonCore.AgentSupervisor, pid)
    end
  end

  def list_agents do
    DynamicSupervisor.which_children(AxonCore.AgentSupervisor)
  end

  def status do
    %{
      http_client: Process.whereis(AxonCore.PydanticHTTPClient) != nil,
      tool_registry: Process.whereis(AxonCore.PydanticToolRegistry) != nil,
      agent_supervisor: Process.whereis(AxonCore.AgentSupervisor) != nil,
      python_env: %{
        path: AxonCore.PythonEnvManager.python_path(),
        env_vars: AxonCore.PythonEnvManager.env_vars()
      }
    }
  end
end
