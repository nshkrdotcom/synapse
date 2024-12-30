defmodule AxonCore.Agent.Supervisor do
  use Supervisor

  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: MyApp.AgentRegistry},
      {Registry, keys: :unique, name: MyApp.MonitorRegistry},
      {DynamicSupervisor, name: MyApp.AgentSupervisor},
      {DynamicSupervisor, name: MyApp.MonitorSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_agent(name) do
    with {:ok, agent_pid} <- DynamicSupervisor.start_child(
           MyApp.AgentSupervisor,
           {MyApp.Agent.Server, [name: name]}
         ),
         {:ok, _monitor_pid} <- DynamicSupervisor.start_child(
           MyApp.MonitorSupervisor,
           {MyApp.Agent.Monitor, [name: name, agent_pid: agent_pid]}
         ) do
      {:ok, agent_pid}
    else
      error ->
        Logger.error("Failed to start agent system: #{inspect(error)}")
        error
    end
  end
end
