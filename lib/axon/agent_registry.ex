defmodule AxonCore.AgentRegistry do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    # Use an ETS table or a Map to store agent information
    {:ok, %{}}
  end

  def lookup(_registry, agent_id) do
    {agent_id, nil}
  end

  # def stop_agent(agent_id) do
  #   case Registry.lookup(Axon.AgentRegistry, agent_id) do
  #     [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
  #     [] -> {:error, :not_found}
  #   end
  # end



  # Add functions to register, unregister, lookup agents, etc.
end
