defmodule Synapse.AgentRegistry do
  @moduledoc """
  Registry for managing agent instances and ensuring idempotent spawning.

  Provides a centralized way to track active agents and prevent duplicate
  spawning of the same agent instance.
  """

  use GenServer
  require Logger

  @type agent_id :: String.t()
  @type agent_module :: module()
  @type agent_pid :: pid()

  ## Client API

  @doc """
  Starts the agent registry.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets or spawns an agent, ensuring only one instance exists.

  Returns `{:ok, pid, started?}` where `started?` is `true` when a new agent
  process was launched and `false` when an existing agent was reused.
  Returns `{:error, reason}` if spawning failed.

  ## Examples

      {:ok, pid} = AgentRegistry.get_or_spawn(registry, "security_specialist", SecurityAgent)
      {:ok, ^pid} = AgentRegistry.get_or_spawn(registry, "security_specialist", SecurityAgent)
  """
  @spec get_or_spawn(GenServer.server(), agent_id(), agent_module(), keyword()) ::
          {:ok, agent_pid(), boolean()} | {:error, term()}
  def get_or_spawn(registry \\ __MODULE__, agent_id, agent_module, opts \\ []) do
    GenServer.call(registry, {:get_or_spawn, agent_id, agent_module, opts})
  end

  @doc """
  Looks up an agent by ID.

  Returns `{:ok, pid}` if found, `{:error, :not_found}` otherwise.
  """
  @spec lookup(GenServer.server(), agent_id()) :: {:ok, agent_pid()} | {:error, :not_found}
  def lookup(registry \\ __MODULE__, agent_id) do
    GenServer.call(registry, {:lookup, agent_id})
  end

  @doc """
  Registers an already-started agent.

  Returns `:ok` if successful, `{:error, :already_registered}` if agent_id is taken.
  """
  @spec register(GenServer.server(), agent_id(), agent_pid()) ::
          :ok | {:error, :already_registered}
  def register(registry \\ __MODULE__, agent_id, pid) do
    GenServer.call(registry, {:register, agent_id, pid})
  end

  @doc """
  Unregisters an agent.
  """
  @spec unregister(GenServer.server(), agent_id()) :: :ok
  def unregister(registry \\ __MODULE__, agent_id) do
    GenServer.call(registry, {:unregister, agent_id})
  end

  @doc """
  Lists all registered agents.

  Returns a list of `{agent_id, pid}` tuples.
  """
  @spec list_agents(GenServer.server()) :: [{agent_id(), agent_pid()}]
  def list_agents(registry \\ __MODULE__) do
    GenServer.call(registry, :list_agents)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # agents: %{agent_id => pid}
    # monitors: %{monitor_ref => agent_id}
    state = %{
      agents: %{},
      monitors: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_or_spawn, agent_id, agent_module, opts}, from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        # Spawn new agent
        case spawn_agent(agent_module, agent_id, opts) do
          {:ok, pid} ->
            # Monitor the agent
            ref = Process.monitor(pid)

            new_state = %{
              state
              | agents: Map.put(state.agents, agent_id, pid),
                monitors: Map.put(state.monitors, ref, agent_id)
            }

            Logger.debug("AgentRegistry: Spawned new agent",
              agent_id: agent_id,
              module: agent_module,
              pid: inspect(pid)
            )

            {:reply, {:ok, pid, true}, new_state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end

      pid when is_pid(pid) ->
        # Agent already exists
        if Process.alive?(pid) do
          {:reply, {:ok, pid, false}, state}
        else
          # Stale entry, remove and retry
          new_state = %{state | agents: Map.delete(state.agents, agent_id)}
          handle_call({:get_or_spawn, agent_id, agent_module, opts}, from, new_state)
        end
    end
  end

  @impl true
  def handle_call({:lookup, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      pid -> {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call({:register, agent_id, pid}, _from, state) do
    if Map.has_key?(state.agents, agent_id) do
      {:reply, {:error, :already_registered}, state}
    else
      ref = Process.monitor(pid)

      new_state = %{
        state
        | agents: Map.put(state.agents, agent_id, pid),
          monitors: Map.put(state.monitors, ref, agent_id)
      }

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    new_state = %{state | agents: Map.delete(state.agents, agent_id)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agents = Map.to_list(state.agents)
    {:reply, agents, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        Logger.debug("AgentRegistry: Agent process terminated", agent_id: agent_id)

        new_state = %{
          state
          | agents: Map.delete(state.agents, agent_id),
            monitors: Map.delete(state.monitors, ref)
        }

        {:noreply, new_state}
    end
  end

  ## Private Helpers

  defp spawn_agent(agent_module, agent_id, opts) do
    # Stage 2: Support both GenServer agents and stateless agents
    # Check if module implements start_link/1 (GenServer)
    Code.ensure_loaded(agent_module)

    if function_exported?(agent_module, :start_link, 1) do
      Logger.debug("AgentRegistry: Starting GenServer agent",
        agent_id: agent_id,
        module: agent_module
      )

      start_opts =
        opts
        |> Keyword.put(:id, agent_id)
        |> Keyword.delete(:supervisor)

      case Keyword.get(opts, :supervisor) do
        nil ->
          agent_module.start_link(start_opts)

        supervisor_name ->
          Synapse.SpecialistSupervisor.start_specialist(supervisor_name, agent_module, start_opts)
      end
    else
      # It's a stateless agent module (Stage 1 behavior)
      Logger.debug("AgentRegistry: Starting stateless agent",
        agent_id: agent_id,
        module: agent_module
      )

      agent = agent_module.new(agent_id)

      # Start a simple holder process for the agent
      pid = spawn_link(fn -> agent_holder_loop(agent) end)

      {:ok, pid}
    end
  rescue
    error -> {:error, error}
  end

  defp agent_holder_loop(agent) do
    receive do
      {:get_agent, from} ->
        send(from, {:agent, agent})
        agent_holder_loop(agent)

      {:update_agent, new_agent, from} ->
        send(from, :ok)
        agent_holder_loop(new_agent)

      :stop ->
        :ok
    end
  end
end
