# Synapse Orchestrator Implementation Guide

**Purpose**: Step-by-step guide to building the configuration-driven orchestrator

## Overview

This guide shows how to build `Synapse.Orchestrator` - a compile-time library that transforms agent configurations into running multi-agent systems on top of Jido.

**Goal**: Replace our 900 lines of GenServer code with 150 lines of configuration.

## Prerequisites

Before starting, understand:
- ✅ Stage 2 implementation (the baseline we're generalizing)
- ✅ Jido.Agent.Server patterns
- ✅ Jido.Signal.Bus and routing
- ✅ Jido.Exec action execution
- ✅ NimbleOptions for schemas

## Implementation Order

### Step 1: Configuration Schema (2 days)

**File**: `lib/synapse/orchestrator/config.ex`

#### 1.1: Define Basic Schema

```elixir
defmodule Synapse.Orchestrator.Config do
  @moduledoc """
  Agent configuration schema and validation.
  """

  @type agent_config :: %{
    required(:id) => atom(),
    required(:type) => :specialist | :orchestrator | :custom,
    required(:actions) => [module()],
    required(:signals) => %{
      required(:subscribes) => [String.t()],
      required(:emits) => [String.t()]
    },
    optional(:result_builder) => (list(), any() -> map()),
    optional(:orchestration) => map(),
    optional(:state_schema) => keyword(),
    optional(:bus) => atom(),
    optional(:registry) => atom()
  }

  # NimbleOptions schema
  @schema NimbleOptions.new!(
    id: [
      type: :atom,
      required: true,
      doc: "Unique agent identifier"
    ],
    type: [
      type: {:in, [:specialist, :orchestrator, :custom]},
      required: true,
      doc: "Agent type/archetype"
    ],
    actions: [
      type: {:list, :atom},
      required: true,
      doc: "Action modules the agent can execute"
    ],
    signals: [
      type: :map,
      required: true,
      doc: "Signal subscription and emission configuration",
      keys: [
        subscribes: [type: {:list, :string}, required: true],
        emits: [type: {:list, :string}, required: true]
      ]
    ],
    result_builder: [
      type: {:or, [:mfa, {:fun, 2}]},
      doc: "Function to build results: (action_results, context) -> result_map"
    ],
    orchestration: [
      type: :map,
      doc: "Orchestrator-specific configuration",
      keys: [
        classify_fn: [type: {:or, [:mfa, {:fun, 1}]}, required: true],
        spawn_specialists: [type: {:list, :atom}, required: true],
        aggregation_fn: [type: {:or, [:mfa, {:fun, 2}]}, required: true],
        fast_path_fn: [type: {:or, [:mfa, {:fun, 2}]}]
      ]
    ],
    state_schema: [
      type: :keyword_list,
      default: [],
      doc: "NimbleOptions schema for agent state"
    ],
    bus: [
      type: :atom,
      default: :synapse_bus,
      doc: "Signal bus name"
    ],
    registry: [
      type: :atom,
      default: :synapse_registry,
      doc: "Agent registry name"
    ]
  )

  @doc "Validates a single agent configuration"
  @spec validate(map()) :: {:ok, agent_config()} | {:error, term()}
  def validate(config) do
    case NimbleOptions.validate(config, @schema) do
      {:ok, validated} ->
        # Additional custom validation
        validate_actions_exist(validated)

      {:error, _} = error ->
        error
    end
  end

  defp validate_actions_exist(config) do
    # Check all action modules are loaded
    missing = Enum.reject(config.actions, &Code.ensure_loaded?/1)

    if Enum.empty?(missing) do
      {:ok, config}
    else
      {:error, "Actions not found: #{inspect(missing)}"}
    end
  end

  @doc "Validates multiple configs"
  @spec validate_all([map()]) :: {:ok, [agent_config()]} | {:error, term()}
  def validate_all(configs) when is_list(configs) do
    results = Enum.map(configs, &validate/1)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {valid, []} ->
        {:ok, Enum.map(valid, fn {:ok, config} -> config end)}

      {_, errors} ->
        {:error, errors}
    end
  end

  @doc "Loads configs from file"
  @spec load(String.t()) :: {:ok, [agent_config()]} | {:error, term()}
  def load(file_path) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        {configs, _} = Code.eval_string(content)
        validate_all(configs)

      {:error, reason} ->
        {:error, "Failed to read config: #{reason}"}
    end
  end

  @doc "Loads configs from module"
  def load(module) when is_atom(module) do
    configs = apply(module, :agent_configs, [])
    validate_all(configs)
  end
end
```

#### 1.2: Write Configuration Tests

```elixir
defmodule Synapse.Orchestrator.ConfigTest do
  use ExUnit.Case

  describe "validate/1" do
    test "validates specialist config" do
      config = %{
        id: :test_specialist,
        type: :specialist,
        actions: [Synapse.Actions.Echo],
        signals: %{
          subscribes: ["test.input"],
          emits: ["test.output"]
        }
      }

      assert {:ok, validated} = Config.validate(config)
      assert validated.id == :test_specialist
    end

    test "requires id field" do
      config = %{
        type: :specialist,
        actions: [],
        signals: %{subscribes: [], emits: []}
      }

      assert {:error, _} = Config.validate(config)
    end

    test "validates action modules exist" do
      config = %{
        id: :test,
        type: :specialist,
        actions: [NonExistent.Module],
        signals: %{subscribes: [], emits: []}
      }

      assert {:error, reason} = Config.validate(config)
      assert reason =~ "Actions not found"
    end
  end

  describe "load/1" do
    test "loads from file" do
      # Create temp config file
      config_content = """
      [
        %{
          id: :test_agent,
          type: :specialist,
          actions: [Synapse.Actions.Echo],
          signals: %{subscribes: ["input"], emits: ["output"]}
        }
      ]
      """

      File.write!("/tmp/test_agents.exs", config_content)

      assert {:ok, [config]} = Config.load("/tmp/test_agents.exs")
      assert config.id == :test_agent
    end
  end
end
```

### Step 2: Agent Factory (2 days)

**File**: `lib/synapse/orchestrator/agent_factory.ex`

#### 2.1: Implement Specialist Factory

```elixir
defmodule Synapse.Orchestrator.AgentFactory do
  @moduledoc """
  Transforms agent configurations into running Jido.Agent.Server instances.
  """

  require Logger
  alias Synapse.Orchestrator.Behaviors

  @doc "Spawns an agent from configuration"
  @spec spawn(map(), atom(), atom()) :: {:ok, pid()} | {:error, term()}
  def spawn(config, bus, registry) do
    Logger.info("Spawning agent from config", agent_id: config.id, type: config.type)

    case config.type do
      :specialist -> spawn_specialist(config, bus, registry)
      :orchestrator -> spawn_orchestrator(config, bus, registry)
      :custom -> spawn_custom(config, bus, registry)
    end
  end

  ## Specialist Factory

  defp spawn_specialist(config, bus, _registry) do
    # Build Jido.Agent.Server options
    server_opts = [
      id: to_string(config.id),
      bus: bus,

      # Register all configured actions
      actions: config.actions,

      # Build signal subscription routes
      routes: build_specialist_routes(config, bus),

      # Configure state schema if provided
      schema: config[:state_schema] || []
    ]

    # Start Jido.Agent.Server with these options
    # THIS is the key - we're delegating to Jido's infrastructure
    Jido.Agent.Server.start_link(server_opts)
  end

  defp build_specialist_routes(config, bus) do
    # For each subscribed signal pattern, create a route
    Enum.map(config.signals.subscribes, fn signal_pattern ->
      {
        signal_pattern,
        build_specialist_handler(config, bus)
      }
    end)
  end

  defp build_specialist_handler(config, bus) do
    # Return a function that Jido.Agent.Server will call when signal matches
    fn signal ->
      review_id = get_in(signal.data, [:review_id])
      start_time = System.monotonic_time(:millisecond)

      # Execute all configured actions in parallel
      results =
        config.actions
        |> Task.async_stream(fn action ->
          Jido.Exec.run(action, signal.data, %{})
        end)
        |> Enum.to_list()
        |> Enum.map(fn {:ok, result} -> result end)

      runtime_ms = System.monotonic_time(:millisecond) - start_time

      # Build result using configured builder
      result_data =
        if config[:result_builder] do
          config.result_builder.(results, review_id)
        else
          # Default result builder
          Behaviors.build_specialist_result(results, review_id, to_string(config.id))
        end

      # Add runtime tracking
      result_data = put_in(result_data[:metadata][:runtime_ms], runtime_ms)

      # Emit result signal to configured output
      emit_result_signal(result_data, config, bus)

      # Return for state update
      {:ok, %{last_review: review_id, last_result: result_data}}
    end
  end

  defp emit_result_signal(result_data, config, bus) do
    result_signal_type = hd(config.signals.emits)
    review_id = result_data.review_id

    {:ok, signal} = Jido.Signal.new(%{
      type: result_signal_type,
      source: "/synapse/agents/#{config.id}",
      subject: "jido://review/#{review_id}",
      data: result_data
    })

    {:ok, _} = Jido.Signal.Bus.publish(bus, [signal])

    Logger.info("Agent emitted result",
      agent_id: config.id,
      review_id: review_id,
      signal_type: result_signal_type
    )
  end
end
```

#### 2.2: Test Specialist Factory

```elixir
defmodule Synapse.Orchestrator.AgentFactoryTest do
  use ExUnit.Case, async: false

  alias Synapse.Orchestrator.AgentFactory

  setup do
    bus = :synapse_bus
    registry = :synapse_registry

    %{bus: bus, registry: registry}
  end

  describe "spawn_specialist/3" do
    test "spawns specialist from config", %{bus: bus, registry: registry} do
      config = %{
        id: :test_specialist,
        type: :specialist,
        actions: [Synapse.Actions.Echo],
        signals: %{
          subscribes: ["test.request"],
          emits: ["test.result"]
        }
      }

      {:ok, pid} = AgentFactory.spawn(config, bus, registry)

      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "specialist processes signals", %{bus: bus, registry: registry} do
      config = %{
        id: :echo_specialist,
        type: :specialist,
        actions: [Synapse.Actions.Echo],
        signals: %{
          subscribes: ["echo.request"],
          emits: ["echo.result"]
        }
      }

      {:ok, pid} = AgentFactory.spawn(config, bus, registry)

      # Subscribe to results
      {:ok, _sub} = Jido.Signal.Bus.subscribe(
        bus,
        "echo.result",
        dispatch: {:pid, target: self(), delivery_mode: :async}
      )

      # Send test signal
      {:ok, signal} = Jido.Signal.new(%{
        type: "echo.request",
        source: "/test",
        data: %{
          review_id: "test_#{System.unique_integer()}",
          message: "hello"
        }
      })

      {:ok, _} = Jido.Signal.Bus.publish(bus, [signal])

      # Should receive result
      assert_receive {:signal, result}, 2000
      assert result.type == "echo.result"

      # Cleanup
      GenServer.stop(pid)
    end
  end
end
```

### Step 3: Runtime Manager (2 days)

**File**: `lib/synapse/orchestrator/runtime.ex`

#### 3.1: Implement Core Runtime

```elixir
defmodule Synapse.Orchestrator.Runtime do
  @moduledoc """
  Runtime manager for configuration-driven agent systems.

  Implements Puppet-style continuous reconciliation to maintain
  desired agent topology from configuration.
  """

  use GenServer
  require Logger

  alias Synapse.Orchestrator.{Config, AgentFactory}

  defstruct [
    :config_source,
    :agent_configs,
    :running_agents,
    :bus,
    :registry,
    :reconcile_interval,
    :last_reconcile,
    :reconcile_count,
    :monitors
  ]

  ## Client API

  @doc "Starts the runtime manager"
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Lists all running agents"
  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  @doc "Gets agent configuration"
  def get_agent_config(agent_id) do
    GenServer.call(__MODULE__, {:get_config, agent_id})
  end

  @doc "Gets agent status"
  def agent_status(agent_id) do
    GenServer.call(__MODULE__, {:agent_status, agent_id})
  end

  @doc "Reloads configuration from source"
  def reload_config do
    GenServer.call(__MODULE__, :reload_config)
  end

  @doc "Adds new agent at runtime"
  def add_agent(config) do
    GenServer.call(__MODULE__, {:add_agent, config})
  end

  @doc "Removes agent at runtime"
  def remove_agent(agent_id) do
    GenServer.call(__MODULE__, {:remove_agent, agent_id})
  end

  @doc "System health check"
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    config_source = Keyword.fetch!(opts, :config_source)

    # Load and validate configurations
    case Config.load(config_source) do
      {:ok, agent_configs} ->
        state = %__MODULE__{
          config_source: config_source,
          agent_configs: agent_configs,
          running_agents: %{},
          monitors: %{},
          bus: Keyword.get(opts, :bus, :synapse_bus),
          registry: Keyword.get(opts, :registry, :synapse_registry),
          reconcile_interval: Keyword.get(opts, :reconcile_interval, 5000),
          last_reconcile: DateTime.utc_now(),
          reconcile_count: 0
        }

        # Trigger initial reconciliation
        send(self(), :reconcile)

        Logger.info("Orchestrator started",
          agent_count: length(agent_configs),
          config_source: config_source
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, {:config_error, reason}}
    end
  end

  @impl true
  def handle_info(:reconcile, state) do
    # Reconcile desired vs actual state
    new_state = reconcile_agents(state)

    # Schedule next reconciliation
    Process.send_after(self(), :reconcile, state.reconcile_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Find which agent died
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        Logger.warning("Agent terminated",
          agent_id: agent_id,
          pid: inspect(pid),
          reason: reason
        )

        # Remove from tracking
        new_state = %{state |
          running_agents: Map.delete(state.running_agents, agent_id),
          monitors: Map.delete(state.monitors, ref)
        }

        # Reconciliation will respawn it
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    {:reply, state.running_agents, state}
  end

  @impl true
  def handle_call({:get_config, agent_id}, _from, state) do
    config = Enum.find(state.agent_configs, &(&1.id == agent_id))
    {:reply, {:ok, config}, state}
  end

  @impl true
  def handle_call({:agent_status, agent_id}, _from, state) do
    case Map.get(state.running_agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pid ->
        config = Enum.find(state.agent_configs, &(&1.id == agent_id))
        status = %{
          pid: pid,
          alive: Process.alive?(pid),
          config: config,
          uptime_ms: 0  # TODO: track actual uptime
        }
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call(:reload_config, _from, state) do
    case Config.load(state.config_source) do
      {:ok, new_configs} ->
        new_state = %{state | agent_configs: new_configs}

        # Trigger immediate reconciliation
        send(self(), :reconcile)

        {:reply, {:ok, length(new_configs)}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:add_agent, config}, _from, state) do
    case Config.validate(config) do
      {:ok, validated} ->
        # Add to configs
        new_configs = [validated | state.agent_configs]
        new_state = %{state | agent_configs: new_configs}

        # Spawn immediately
        case spawn_agent_from_config(validated, new_state) do
          {:ok, pid, updated_state} ->
            {:reply, {:ok, pid}, updated_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_agent, agent_id}, _from, state) do
    # Remove from configs
    new_configs = Enum.reject(state.agent_configs, &(&1.id == agent_id))

    # Stop agent if running
    case Map.get(state.running_agents, agent_id) do
      nil ->
        {:reply, :ok, %{state | agent_configs: new_configs}}

      pid ->
        GenServer.stop(pid, :normal)

        new_state = %{state |
          agent_configs: new_configs,
          running_agents: Map.delete(state.running_agents, agent_id)
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health = %{
      total_agents: length(state.agent_configs),
      running_agents: map_size(state.running_agents),
      failed_agents: length(state.agent_configs) - map_size(state.running_agents),
      reconcile_count: state.reconcile_count,
      last_reconcile: state.last_reconcile,
      uptime_ms: DateTime.diff(DateTime.utc_now(), state.last_reconcile, :millisecond)
    }

    {:reply, health, state}
  end

  ## Private Functions

  defp reconcile_agents(state) do
    Logger.debug("Reconciling agents", desired: length(state.agent_configs))

    # Spawn missing agents
    state = spawn_missing_agents(state)

    # Verify running agents
    state = verify_running_agents(state)

    # Remove extra agents (not in config)
    state = remove_extra_agents(state)

    # Update metrics
    %{state |
      last_reconcile: DateTime.utc_now(),
      reconcile_count: state.reconcile_count + 1
    }
  end

  defp spawn_missing_agents(state) do
    Enum.reduce(state.agent_configs, state, fn config, acc_state ->
      case Map.get(acc_state.running_agents, config.id) do
        nil ->
          # Not running - spawn it
          case spawn_agent_from_config(config, acc_state) do
            {:ok, _pid, new_state} -> new_state
            {:error, _reason} -> acc_state
          end

        _pid ->
          # Already running
          acc_state
      end
    end)
  end

  defp verify_running_agents(state) do
    Enum.reduce(state.running_agents, state, fn {agent_id, pid}, acc_state ->
      if Process.alive?(pid) do
        acc_state
      else
        Logger.warning("Dead agent detected, will respawn", agent_id: agent_id)

        # Remove dead process (reconciliation will respawn)
        %{acc_state |
          running_agents: Map.delete(acc_state.running_agents, agent_id)
        }
      end
    end)
  end

  defp remove_extra_agents(state) do
    configured_ids = MapSet.new(state.agent_configs, & &1.id)

    Enum.reduce(state.running_agents, state, fn {agent_id, pid}, acc_state ->
      if agent_id in configured_ids do
        acc_state
      else
        # Not in config - terminate gracefully
        Logger.info("Terminating unconfigured agent", agent_id: agent_id)
        GenServer.stop(pid, :normal, 5000)

        %{acc_state |
          running_agents: Map.delete(acc_state.running_agents, agent_id)
        }
      end
    end)
  end

  defp spawn_agent_from_config(config, state) do
    case AgentFactory.spawn(config, state.bus, state.registry) do
      {:ok, pid} ->
        # Monitor the agent
        ref = Process.monitor(pid)

        new_state = %{state |
          running_agents: Map.put(state.running_agents, config.id, pid),
          monitors: Map.put(state.monitors, ref, config.id)
        }

        Logger.info("Agent spawned successfully",
          agent_id: config.id,
          pid: inspect(pid)
        )

        {:ok, pid, new_state}

      {:error, reason} ->
        Logger.error("Failed to spawn agent",
          agent_id: config.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
```

#### 3.2: Test Runtime Manager

```elixir
defmodule Synapse.Orchestrator.RuntimeTest do
  use ExUnit.Case, async: false

  setup do
    # Create test config
    config_content = """
    [
      %{
        id: :test_agent_1,
        type: :specialist,
        actions: [Synapse.Actions.Echo],
        signals: %{subscribes: ["test.input"], emits: ["test.output"]}
      },
      %{
        id: :test_agent_2,
        type: :specialist,
        actions: [Synapse.Actions.Echo],
        signals: %{subscribes: ["test.input"], emits: ["test.output"]}
      }
    ]
    """

    config_file = "/tmp/test_runtime_agents_#{System.unique_integer()}.exs"
    File.write!(config_file, config_content)

    on_exit(fn -> File.rm(config_file) end)

    %{config_file: config_file}
  end

  test "spawns all configured agents", %{config_file: config_file} do
    {:ok, runtime} = Synapse.Orchestrator.Runtime.start_link(
      config_source: config_file,
      reconcile_interval: 10_000
    )

    # Give it time to reconcile
    Process.sleep(100)

    # Check running agents
    running = Synapse.Orchestrator.Runtime.list_agents()

    assert Map.has_key?(running, :test_agent_1)
    assert Map.has_key?(running, :test_agent_2)
    assert Process.alive?(running.test_agent_1)
    assert Process.alive?(running.test_agent_2)

    # Cleanup
    GenServer.stop(runtime)
  end

  test "respawns failed agents", %{config_file: config_file} do
    {:ok, runtime} = Synapse.Orchestrator.Runtime.start_link(
      config_source: config_file,
      reconcile_interval: 100  # Fast reconciliation for testing
    )

    Process.sleep(150)

    # Get agent
    running = Synapse.Orchestrator.Runtime.list_agents()
    original_pid = running.test_agent_1

    # Kill it
    GenServer.stop(original_pid, :kill)
    Process.sleep(50)

    # Trigger reconciliation
    send(runtime, :reconcile)
    Process.sleep(150)

    # Should be respawned
    running = Synapse.Orchestrator.Runtime.list_agents()
    new_pid = running.test_agent_1

    assert new_pid != original_pid
    assert Process.alive?(new_pid)

    # Cleanup
    GenServer.stop(runtime)
  end
end
```

### Step 4: Behavior Library (1 day)

**File**: `lib/synapse/orchestrator/behaviors.ex`

```elixir
defmodule Synapse.Orchestrator.Behaviors do
  @moduledoc """
  Reusable behavior implementations for agent configurations.
  """

  ## Classification Behaviors

  @doc """
  Classifies a code review based on size, labels, and risk.
  """
  def classify_review(review_data) do
    cond do
      review_data.files_changed > 50 ->
        %{path: :deep_review, rationale: "Large change (#{review_data.files_changed} files)"}

      has_critical_labels?(review_data.labels) ->
        %{path: :deep_review, rationale: "Critical labels: #{inspect(review_data.labels)}"}

      review_data.intent == "hotfix" ->
        %{path: :fast_path, rationale: "Hotfix - quick review"}

      review_data.risk_factor > 0.5 ->
        %{path: :deep_review, rationale: "High risk factor: #{review_data.risk_factor}"}

      true ->
        %{path: :fast_path, rationale: "Small, low-risk change"}
    end
  end

  defp has_critical_labels?(labels) do
    critical = ["security", "performance", "breaking"]
    Enum.any?(labels, &(&1 in critical))
  end

  ## Result Building Behaviors

  @doc """
  Builds a specialist result from action outputs.
  """
  def build_specialist_result(action_results, review_id, agent_name) do
    # Extract findings from all actions
    all_findings = Enum.flat_map(action_results, fn
      {:ok, result} -> Map.get(result, :findings, [])
      {:error, _} -> []
    end)

    # Calculate average confidence
    avg_confidence = calculate_avg_confidence(action_results)

    %{
      review_id: review_id,
      agent: agent_name,
      confidence: avg_confidence,
      findings: all_findings,
      should_escalate: Enum.any?(all_findings, &(&1.severity == :high)),
      metadata: %{
        runtime_ms: 0,  # Filled in by caller
        path: :deep_review,
        actions_run: extract_action_modules(action_results)
      }
    }
  end

  ## Aggregation Behaviors

  @doc """
  Aggregates specialist results into a review summary.
  """
  def aggregate_results(specialist_results, review_state) do
    all_findings = Enum.flat_map(specialist_results, & &1.findings)

    %{
      review_id: review_state.review_id,
      status: :complete,
      severity: calculate_max_severity(all_findings),
      findings: all_findings,
      recommendations: extract_recommendations(all_findings),
      escalations: [],
      metadata: %{
        decision_path: review_state.classification_path,
        specialists_resolved: Enum.map(specialist_results, & &1.agent),
        duration_ms: calculate_duration(review_state)
      }
    }
  end

  ## Helper Functions

  defp calculate_avg_confidence(results) do
    confidences = Enum.flat_map(results, fn
      {:ok, result} -> [Map.get(result, :confidence, 0.0)]
      {:error, _} -> []
    end)

    if length(confidences) > 0 do
      Enum.sum(confidences) / length(confidences)
    else
      0.0
    end
  end

  defp extract_action_modules(results) do
    Enum.flat_map(results, fn
      {:ok, result} -> [result]
      {:error, _} -> []
    end)
  end

  defp calculate_max_severity(findings) do
    severities = Enum.map(findings, & &1.severity)

    cond do
      :high in severities -> :high
      :medium in severities -> :medium
      :low in severities -> :low
      true -> :none
    end
  end

  defp extract_recommendations(findings) do
    findings
    |> Enum.filter(&(&1.severity in [:high, :medium]))
    |> Enum.map(& &1.recommendation)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp calculate_duration(review_state) do
    if review_state.start_time do
      System.monotonic_time(:millisecond) - review_state.start_time
    else
      0
    end
  end
end
```

### Step 5: Example Configuration (30 mins)

**File**: `config/agents.exs`

```elixir
# Synapse Multi-Agent System Configuration
# This file defines all agents in the system declaratively

alias Synapse.Orchestrator.Behaviors

[
  # Security Specialist Agent
  %{
    id: :security_specialist,
    type: :specialist,

    actions: [
      Synapse.Actions.Security.CheckSQLInjection,
      Synapse.Actions.Security.CheckXSS,
      Synapse.Actions.Security.CheckAuthIssues
    ],

    signals: %{
      subscribes: ["review.request"],
      emits: ["review.result"]
    },

    result_builder: fn results, review_id ->
      Behaviors.build_specialist_result(results, review_id, "security_specialist")
    end,

    state_schema: [
      review_history: [type: {:list, :map}, default: []],
      learned_patterns: [type: {:list, :map}, default: []],
      scar_tissue: [type: {:list, :map}, default: []]
    ]
  },

  # Performance Specialist Agent
  %{
    id: :performance_specialist,
    type: :specialist,

    actions: [
      Synapse.Actions.Performance.CheckComplexity,
      Synapse.Actions.Performance.CheckMemoryUsage,
      Synapse.Actions.Performance.ProfileHotPath
    ],

    signals: %{
      subscribes: ["review.request"],
      emits: ["review.result"]
    },

    result_builder: fn results, review_id ->
      Behaviors.build_specialist_result(results, review_id, "performance_specialist")
    end,

    state_schema: [
      review_history: [type: {:list, :map}, default: []],
      learned_patterns: [type: {:list, :map}, default: []],
      scar_tissue: [type: {:list, :map}, default: []]
    ]
  },

  # Coordinator Agent
  %{
    id: :coordinator,
    type: :orchestrator,

    actions: [
      Synapse.Actions.Review.ClassifyChange,
      Synapse.Actions.Review.GenerateSummary
    ],

    signals: %{
      subscribes: ["review.request", "review.result"],
      emits: ["review.summary"]
    },

    orchestration: %{
      classify_fn: &Behaviors.classify_review/1,
      spawn_specialists: [:security_specialist, :performance_specialist],
      aggregation_fn: &Behaviors.aggregate_results/2
    },

    state_schema: [
      review_count: [type: :integer, default: 0],
      active_reviews: [type: :map, default: %{}]
    ]
  }
]
```

### Step 6: Integration (1 day)

**File**: `lib/synapse/application.ex`

```elixir
defmodule Synapse.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Core infrastructure
      {Jido.Signal.Bus, name: :synapse_bus},
      {Synapse.AgentRegistry, name: :synapse_registry},

      # THE ORCHESTRATOR - replaces all hardcoded agent modules
      {Synapse.Orchestrator.Runtime,
        config_source: "config/agents.exs",
        bus: :synapse_bus,
        registry: :synapse_registry,
        reconcile_interval: 5_000
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Testing the Complete System

### Integration Test

```elixir
defmodule Synapse.Orchestrator.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "complete orchestration via configuration" do
    # Start system with config
    {:ok, _runtime} = Synapse.Orchestrator.Runtime.start_link(
      config_source: "config/agents.exs"
    )

    Process.sleep(200)  # Let agents spawn

    # Subscribe to summary
    {:ok, _} = Jido.Signal.Bus.subscribe(
      :synapse_bus,
      "review.summary",
      dispatch: {:pid, target: self(), delivery_mode: :async}
    )

    # Publish review request (same as Stage 2)
    {:ok, signal} = Jido.Signal.new(%{
      type: "review.request",
      source: "/test/orchestrator",
      data: %{
        review_id: "orch_test_#{System.unique_integer()}",
        diff: "+ SQL injection test",
        files_changed: 60,
        labels: ["security"],
        intent: "feature",
        risk_factor: 0.7,
        language: "elixir",
        metadata: %{}
      }
    })

    {:ok, _} = Jido.Signal.Bus.publish(:synapse_bus, [signal])

    # Should receive summary
    assert_receive {:signal, summary}, 5000

    assert summary.type == "review.summary"
    assert summary.data.status == :complete
    assert length(summary.data.metadata.specialists_resolved) == 2
  end
end
```

## Rollout Plan

### Phase 1: Parallel Implementation (Week 1)
- Keep existing GenServer agents
- Build orchestrator alongside
- Test equivalence

### Phase 2: Feature Parity (Week 2)
- Verify all Stage 2 functionality works via config
- Run both systems in parallel
- Compare outputs

### Phase 3: Migration (Week 3)
- Switch Application.start to use orchestrator
- Remove old GenServer modules
- Update documentation

### Phase 4: Enhancement (Week 4)
- Add hot reload
- Add templates
- Add discovery API
- Performance tuning

## Validation Criteria

✅ **All 177 tests pass** with orchestrator
✅ **Stage2Demo.run()** produces identical output
✅ **88% code reduction** achieved
✅ **<5s respawn time** for failed agents
✅ **Hot reload** works without restart
✅ **Performance** matches or exceeds hardcoded version

---

**This implementation transforms Synapse from a hardcoded multi-agent system into a declarative orchestration platform.**
