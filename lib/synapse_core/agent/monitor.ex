defmodule SynapseCore.Agent.Monitor do
  use GenServer
  require Logger

  @check_interval 30_000  # Check every 30 seconds
  @reconnect_delay 5_000  # Wait 5 seconds before reconnecting

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:name]))
  end

  def init(opts) do
    Process.send_after(self(), :check_health, @check_interval)
    {:ok, %{agent: opts[:agent_pid], name: opts[:name], status: :ok}}
  end

  def handle_info(:check_health, %{agent: pid} = state) do
    new_state = check_agent_health(pid, state)
    Process.send_after(self(), :check_health, @check_interval)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{agent: pid} = state) do
    Logger.error("Agent #{state.name} went down: #{inspect(reason)}")
    new_state = handle_agent_crash(state)
    {:noreply, new_state}
  end

  # Private functions

  defp check_agent_health(pid, state) do
    case check_grpc_connection(pid) do
      :ok ->
        %{state | status: :ok}
      {:error, reason} ->
        Logger.info("Agent #{state.name} health check failed: #{inspect(reason)}")
        handle_unhealthy_agent(state)
    end
  end

  defp check_grpc_connection(pid) do
    try do
      GenServer.call(pid, :ping, 5000)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
    end
  end

  defp handle_unhealthy_agent(%{status: :ok} = state) do
    Logger.info("Attempting to restart agent #{state.name}")
    case restart_agent(state.name) do
      {:ok, new_pid} ->
        %{state | agent: new_pid, status: :recovering}
      {:error, reason} ->
        Logger.error("Failed to restart agent #{state.name}: #{inspect(reason)}")
        %{state | status: :error}
    end
  end

  defp handle_unhealthy_agent(state), do: state

  defp handle_agent_crash(state) do
    Process.sleep(@reconnect_delay)
    case restart_agent(state.name) do
      {:ok, new_pid} ->
        %{state | agent: new_pid, status: :recovering}
      {:error, _reason} ->
        %{state | status: :error}
    end
  end

  defp restart_agent(name) do
    case DynamicSupervisor.start_child(
      MyApp.AgentSupervisor,
      {MyApp.Agent.Server, [name: name]}
    ) do
      {:ok, pid} -> {:ok, pid}
      error -> {:error, error}
    end
  end

  defp via_tuple(name) do
    {:via, Registry, {MyApp.MonitorRegistry, name}}
  end
end
