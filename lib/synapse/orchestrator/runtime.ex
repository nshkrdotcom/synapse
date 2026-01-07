defmodule Synapse.Orchestrator.Runtime do
  @moduledoc """
  GenServer responsible for keeping declaratively defined agents running.

  The runtime watches a configuration source (file or module), validates each
  entry into a `%Synapse.Orchestrator.AgentConfig{}` struct, and reconciles that
  desired topology against currently running processes. Missing agents are
  spawned through `Synapse.Orchestrator.AgentFactory`, stale ones are retired,
  and crashed processes are respawned on the next reconciliation pass.
  """

  use GenServer

  require Logger

  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.Orchestrator.AgentFactory
  alias Synapse.Orchestrator.Runtime.{RunningAgent, State}
  alias Synapse.Orchestrator.Skill
  alias Synapse.Orchestrator.Skill.Registry, as: SkillRegistry

  @type option ::
          {:config_source, String.t() | module()}
          | {:router, atom() | nil}
          | {:registry, atom() | nil}
          | {:reconcile_interval, pos_integer()}
          | {:skill_directories, [String.t()]}

  @default_interval 5_000

  # Public API ----------------------------------------------------------------

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @doc """
  Triggers an immediate reconciliation cycle.
  """
  @spec reload(pid()) :: :ok
  def reload(server) do
    GenServer.cast(server, :reload)
  end

  @doc """
  Returns information about currently running agents.
  """
  @spec list_agents(pid()) :: [RunningAgent.t()]
  def list_agents(server) do
    GenServer.call(server, :list_agents)
  end

  @doc """
  Returns a metadata summary of discovered skills.
  """
  @spec skill_metadata(pid()) :: String.t()
  def skill_metadata(server) do
    GenServer.call(server, :skill_metadata)
  end

  @doc """
  Returns the configuration for a specific agent.
  """
  @spec get_agent_config(pid(), atom()) :: {:ok, AgentConfig.t()} | {:error, :not_found}
  def get_agent_config(server, agent_id) do
    GenServer.call(server, {:get_agent_config, agent_id})
  end

  @doc """
  Returns the status information for a specific agent.
  """
  @spec agent_status(pid(), atom()) ::
          {:ok,
           %{
             pid: pid(),
             alive?: boolean(),
             config: AgentConfig.t(),
             running_agent: RunningAgent.t()
           }}
          | {:error, :not_found}
  def agent_status(server, agent_id) do
    GenServer.call(server, {:agent_status, agent_id})
  end

  @doc """
  Returns overall health information about the orchestrator.
  """
  @spec health_check(pid()) :: %{
          total: non_neg_integer(),
          running: non_neg_integer(),
          failed: non_neg_integer(),
          reconcile_count: non_neg_integer(),
          last_reconcile: DateTime.t() | nil
        }
  def health_check(server) do
    GenServer.call(server, :health_check)
  end

  @doc """
  Dynamically adds an agent to the runtime.
  """
  @spec add_agent(GenServer.server(), map() | keyword()) :: {:ok, pid()} | {:error, term()}
  def add_agent(server, config) do
    GenServer.call(server, {:add_agent, config})
  end

  @doc """
  Removes an agent from the runtime.
  """
  @spec remove_agent(pid(), atom()) :: :ok | {:error, :not_found}
  def remove_agent(server, agent_id) do
    GenServer.call(server, {:remove_agent, agent_id})
  end

  @doc """
  Gets skill metadata by ID (without loading the body).
  """
  @spec get_skill(pid(), String.t()) :: {:ok, Skill.t()} | {:error, :not_found | :no_registry}
  def get_skill(server, skill_id) do
    GenServer.call(server, {:get_skill, skill_id})
  end

  @doc """
  Loads the full skill body for a given skill ID.
  """
  @spec load_skill_body(pid(), String.t()) :: {:ok, Skill.t()} | {:error, term()}
  def load_skill_body(server, skill_id) do
    GenServer.call(server, {:load_skill_body, skill_id})
  end

  @doc """
  Lists all available skills (metadata only).
  """
  @spec list_skills(pid()) :: [Skill.t()] | {:error, :no_registry}
  def list_skills(server) do
    GenServer.call(server, :list_skills)
  end

  # GenServer callbacks -------------------------------------------------------

  @impl true
  def init(opts) do
    config_source = Keyword.fetch!(opts, :config_source)
    router = Keyword.get(opts, :router) || default_router()
    registry = Keyword.get(opts, :registry)
    reconcile_interval = Keyword.get(opts, :reconcile_interval, @default_interval)
    include_types = Keyword.get(opts, :include_types, :all)
    skill_dirs = Keyword.get(opts, :skill_directories)

    state = %State{
      config_source: config_source,
      router: router,
      registry: registry,
      include_types: include_types,
      reconcile_interval: reconcile_interval
    }

    {skill_registry, summary} = initialize_skill_registry(skill_dirs)

    state =
      state
      |> Map.put(:skill_registry, skill_registry)
      |> Map.put(:skills_summary, summary)

    {:ok, state, {:continue, :initial_load}}
  end

  @impl true
  def handle_continue(:initial_load, state) do
    state =
      state
      |> load_configurations()
      |> reconcile_state()

    schedule_reconcile(state.reconcile_interval)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:reload, state) do
    state = state |> load_configurations() |> reconcile_state()
    {:noreply, state}
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    {:reply, Map.values(state.running_agents), state}
  end

  @impl true
  def handle_call(:skill_metadata, _from, %State{skill_registry: nil} = state) do
    {:reply, state.skills_summary, state}
  end

  def handle_call(:skill_metadata, _from, %State{} = state) do
    summary = SkillRegistry.metadata_summary(state.skill_registry)
    {:reply, summary, %{state | skills_summary: summary}}
  end

  @impl true
  def handle_call({:get_agent_config, agent_id}, _from, state) do
    case Enum.find(state.agent_configs, &(&1.id == agent_id)) do
      nil -> {:reply, {:error, :not_found}, state}
      config -> {:reply, {:ok, config}, state}
    end
  end

  @impl true
  def handle_call({:agent_status, agent_id}, _from, state) do
    case Map.get(state.running_agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      running_agent ->
        status = %{
          pid: running_agent.pid,
          alive?: Process.alive?(running_agent.pid),
          config: running_agent.config,
          running_agent: running_agent
        }

        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    total = length(state.agent_configs)
    running_count = map_size(state.running_agents)

    alive_count =
      state.running_agents
      |> Map.values()
      |> Enum.count(&Process.alive?(&1.pid))

    health = %{
      total: total,
      running: alive_count,
      failed: running_count - alive_count,
      reconcile_count: state.reconcile_count,
      last_reconcile: state.last_reconcile
    }

    {:reply, health, state}
  end

  @impl true
  def handle_call({:add_agent, config_input}, _from, state) do
    case AgentConfig.new(config_input) do
      {:ok, config} ->
        add_agent_config(config, state)

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:remove_agent, agent_id}, _from, state) do
    case Enum.find(state.agent_configs, &(&1.id == agent_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _config ->
        {:reply, :ok, remove_agent_config(state, agent_id)}
    end
  end

  @impl true
  def handle_call({:get_skill, _skill_id}, _from, %State{skill_registry: nil} = state) do
    {:reply, {:error, :no_registry}, state}
  end

  def handle_call({:get_skill, skill_id}, _from, state) do
    result = SkillRegistry.get(state.skill_registry, skill_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:load_skill_body, _skill_id}, _from, %State{skill_registry: nil} = state) do
    {:reply, {:error, :no_registry}, state}
  end

  def handle_call({:load_skill_body, skill_id}, _from, state) do
    result = SkillRegistry.load_body(state.skill_registry, skill_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_skills, _from, %State{skill_registry: nil} = state) do
    {:reply, {:error, :no_registry}, state}
  end

  def handle_call(:list_skills, _from, state) do
    skills = SkillRegistry.list(state.skill_registry)
    {:reply, skills, state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    state = state |> load_configurations() |> reconcile_state()
    schedule_reconcile(state.reconcile_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{} = state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {agent_id, monitors} ->
        Logger.warning("Agent crashed", agent_id: agent_id, reason: inspect(reason))
        running_agents = Map.delete(state.running_agents, agent_id)
        send(self(), :reconcile)

        {:noreply,
         %{
           state
           | monitors: monitors,
             running_agents: running_agents,
             metadata: Map.put(state.metadata, :last_down_reason, {agent_id, reason})
         }}
    end
  end

  # Internal helpers ----------------------------------------------------------

  defp add_agent_config(config, state) do
    if Enum.any?(state.agent_configs, &(&1.id == config.id)) do
      {:reply, {:error, :agent_already_exists}, state}
    else
      state
      |> Map.update!(:agent_configs, &[config | &1])
      |> reconcile_state()
      |> reply_with_spawned_agent(config.id)
    end
  end

  defp reply_with_spawned_agent(state, agent_id) do
    case Map.get(state.running_agents, agent_id) do
      nil -> {:reply, {:error, :spawn_failed}, state}
      running_agent -> {:reply, {:ok, running_agent.pid}, state}
    end
  end

  defp remove_agent_config(state, agent_id) do
    state
    |> Map.update!(:agent_configs, fn configs -> Enum.reject(configs, &(&1.id == agent_id)) end)
    |> reconcile_state()
  end

  defp schedule_reconcile(interval) do
    Process.send_after(self(), :reconcile, interval)
  end

  defp initialize_skill_registry(nil) do
    {nil, ""}
  end

  defp initialize_skill_registry(directories) do
    opts =
      []
      |> maybe_put_directories(directories)
      |> Keyword.put(:name, nil)

    case SkillRegistry.start_link(opts) do
      {:ok, pid} ->
        summary = SkillRegistry.metadata_summary(pid)
        {pid, summary}

      {:error, reason} ->
        Logger.warning("Failed to start skill registry", reason: inspect(reason))
        {nil, ""}
    end
  end

  defp maybe_put_directories(opts, directories) when is_list(directories),
    do: Keyword.put(opts, :directories, directories)

  defp maybe_put_directories(opts, _), do: opts

  defp load_configurations(%State{} = state) do
    case fetch_raw_configs(state.config_source) do
      {:ok, raw_configs} ->
        case validate_configs(raw_configs) do
          {:ok, configs} ->
            filtered = filter_configs(configs, state.include_types)
            %{state | agent_configs: filtered}

          {:error, error} ->
            Logger.error("Failed to validate agent configs", error: Exception.message(error))
            state
        end

      {:error, reason} ->
        Logger.error("Failed to load agent configs", reason: inspect(reason))
        state
    end
  end

  defp reconcile_state(%State{} = state) do
    desired = desired_agents(state)

    {running_agents, monitors} = reconcile_desired_agents(desired, state)
    {running_agents, monitors} = stop_removed_agents(desired, state, running_agents, monitors)

    %{
      state
      | running_agents: running_agents,
        monitors: monitors,
        last_reconcile: DateTime.utc_now(),
        reconcile_count: state.reconcile_count + 1
    }
  end

  defp filter_configs(configs, :all), do: configs

  defp filter_configs(configs, types) when is_list(types) do
    Enum.filter(configs, &(&1.type in types))
  end

  defp desired_agents(state) do
    Map.new(state.agent_configs, &{&1.id, &1})
  end

  defp reconcile_desired_agents(desired, state) do
    Enum.reduce(desired, {state.running_agents, state.monitors}, fn {agent_id, config},
                                                                    {agents_acc, monitors_acc} ->
      reconcile_agent(agent_id, config, state, agents_acc, monitors_acc)
    end)
  end

  defp reconcile_agent(agent_id, config, state, agents_acc, monitors_acc) do
    case Map.get(agents_acc, agent_id) do
      %RunningAgent{} = running ->
        maybe_restart_agent(agent_id, running, config, state, agents_acc, monitors_acc)

      nil ->
        start_agent(config, state, agents_acc, monitors_acc, 1, %{})
    end
  end

  defp maybe_restart_agent(agent_id, running, config, state, agents_acc, monitors_acc) do
    if needs_restart?(running, config) do
      Logger.info("Restarting agent", agent_id: agent_id)
      cleanup_agent(running)

      start_agent(
        config,
        state,
        Map.delete(agents_acc, agent_id),
        monitors_acc,
        running.spawn_count + 1,
        running.metadata
      )
    else
      updated = %{running | config: config}
      {Map.put(agents_acc, agent_id, updated), monitors_acc}
    end
  end

  defp needs_restart?(running, config) do
    running.config != config or not Process.alive?(running.pid)
  end

  defp stop_removed_agents(desired, state, running_agents, monitors) do
    Enum.reduce(state.running_agents, {running_agents, monitors}, fn {agent_id, agent},
                                                                     {agents_acc, monitors_acc} ->
      stop_removed_agent(desired, agent_id, agent, agents_acc, monitors_acc)
    end)
  end

  defp stop_removed_agent(desired, agent_id, agent, agents_acc, monitors_acc) do
    if Map.has_key?(desired, agent_id) do
      {agents_acc, monitors_acc}
    else
      Logger.info("Stopping agent removed from config", agent_id: agent_id)
      cleanup_agent(agent)
      {Map.delete(agents_acc, agent_id), Map.delete(monitors_acc, agent.monitor_ref)}
    end
  end

  defp start_agent(config, state, agents_acc, monitors_acc, spawn_count, metadata) do
    case AgentFactory.spawn(config, state.router, state.registry) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        running_agent = %RunningAgent{
          agent_id: config.id,
          pid: pid,
          config: config,
          monitor_ref: ref,
          spawned_at: DateTime.utc_now(),
          spawn_count: spawn_count,
          last_error: nil,
          metadata: metadata
        }

        {
          Map.put(agents_acc, config.id, running_agent),
          Map.put(monitors_acc, ref, config.id)
        }

      {:error, reason} ->
        Logger.error("Failed to spawn agent", agent_id: config.id, reason: inspect(reason))
        {agents_acc, monitors_acc}
    end
  end

  defp default_router do
    Synapse.SignalRouter.fetch().name
  rescue
    _error ->
      reraise ArgumentError,
              "SignalRouter must be started or provided via :router when starting the orchestrator runtime",
              __STACKTRACE__
  end

  defp cleanup_agent(%RunningAgent{} = agent) do
    if Process.alive?(agent.pid) do
      AgentFactory.stop(agent.pid)
    end

    Process.demonitor(agent.monitor_ref, [:flush])
    :ok
  catch
    :exit, _ -> :ok
  end

  defp fetch_raw_configs(source) when is_binary(source) do
    if File.exists?(source) do
      try do
        {value, _binding} = Code.eval_file(source)
        {:ok, value}
      rescue
        error -> {:error, error}
      end
    else
      {:error, :enoent}
    end
  end

  defp fetch_raw_configs(module) when is_atom(module) do
    cond do
      function_exported?(module, :configs, 0) ->
        {:ok, module.configs()}

      function_exported?(module, :agent_configs, 0) ->
        {:ok, module.agent_configs()}

      true ->
        {:error, :unsupported_source}
    end
  end

  defp validate_configs(raw) when is_list(raw) do
    Enum.reduce_while(raw, {:ok, []}, fn entry, {:ok, acc} ->
      case AgentConfig.new(entry) do
        {:ok, config} -> {:cont, {:ok, [config | acc]}}
        {:error, %_{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, configs} -> {:ok, Enum.reverse(configs)}
      error -> error
    end
  end

  defp validate_configs(_other), do: {:error, ArgumentError.exception("config should be a list")}
end
