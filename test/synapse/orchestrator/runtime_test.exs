defmodule Synapse.Orchestrator.RuntimeTest do
  use ExUnit.Case, async: false

  alias Synapse.Orchestrator.Runtime
  alias Synapse.TestSupport.SignalRouterHelpers, as: RouterHelpers

  @moduletag :capture_log

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "synapse_orchestrator_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    config_path = Path.join(tmp_dir, "agents.exs")

    skills_dir = Path.join(tmp_dir, "skills")
    skill_path = Path.join(skills_dir, "demo-skill")
    File.mkdir_p!(skill_path)

    File.write!(
      Path.join(skill_path, "SKILL.md"),
      """
      ---
      name: demo-skill
      description: Demo instructions
      ---
      ## Usage

      Step-by-step guide.
      """
    )

    router = RouterHelpers.start_test_router()

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{config_path: config_path, skills_dir: skills_dir, router: router}
  end

  test "spawns agents and reconciles removal", %{
    config_path: path,
    skills_dir: skills_dir,
    router: router
  } do
    write_config(path, [
      %{
        id: :runtime_agent,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      }
    ])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path,
         reconcile_interval: 50,
         skill_directories: [skills_dir],
         router: router}
      )

    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)

    summary = Runtime.skill_metadata(runtime)
    assert summary =~ "demo-skill"

    write_config(path, [])
    :ok = Runtime.reload(runtime)

    assert eventually(fn -> Runtime.list_agents(runtime) == [] end)
  end

  test "get_agent_config returns config for existing agent", %{config_path: path, router: router} do
    write_config(path, [
      %{
        id: :test_agent,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      }
    ])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)

    assert {:ok, config} = Runtime.get_agent_config(runtime, :test_agent)
    assert config.id == :test_agent
    assert config.type == :specialist
    assert config.actions == [Runtime.Action]
  end

  test "get_agent_config returns error for non-existent agent", %{
    config_path: path,
    router: router
  } do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert {:error, :not_found} = Runtime.get_agent_config(runtime, :nonexistent)
  end

  test "agent_status returns status for running agent", %{config_path: path, router: router} do
    write_config(path, [
      %{
        id: :status_agent,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      }
    ])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)

    assert {:ok, status} = Runtime.agent_status(runtime, :status_agent)
    assert is_pid(status.pid)
    assert status.alive? == true
    assert status.config.id == :status_agent
    assert status.running_agent.agent_id == :status_agent
    assert status.running_agent.spawn_count == 1
  end

  test "agent_status returns error for non-existent agent", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert {:error, :not_found} = Runtime.agent_status(runtime, :nonexistent)
  end

  test "include_types filters agent configs", %{config_path: path, router: router} do
    write_config(path, [
      %{
        id: :specialist_agent,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      },
      %{
        id: :coordinator_agent,
        type: :orchestrator,
        actions: [Runtime.Action],
        signals: canonical_signals(),
        orchestration: %{
          classify_fn: &Synapse.Orchestrator.RuntimeTest.TestOrchestration.classify/1,
          spawn_specialists: [],
          aggregation_fn: &Synapse.Orchestrator.RuntimeTest.TestOrchestration.aggregate/2,
          fast_path_fn: &Synapse.Orchestrator.RuntimeTest.TestOrchestration.fast_path/2
        }
      }
    ])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path, include_types: [:specialist], reconcile_interval: 50, router: router}
      )

    assert eventually(fn ->
             Runtime.list_agents(runtime)
             |> Enum.map(& &1.agent_id)
             |> Enum.sort() == [:specialist_agent]
           end)
  end

  test "health_check returns system health information", %{config_path: path, router: router} do
    write_config(path, [
      %{
        id: :health_agent1,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      },
      %{
        id: :health_agent2,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      }
    ])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 2 end)

    health = Runtime.health_check(runtime)
    assert health.total == 2
    assert health.running == 2
    assert health.failed == 0
    assert health.reconcile_count > 0
    assert health.last_reconcile != nil
  end

  test "health_check with no agents", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    health = Runtime.health_check(runtime)
    assert health.total == 0
    assert health.running == 0
    assert health.failed == 0
  end

  test "add_agent dynamically adds a new agent", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert Runtime.list_agents(runtime) == []

    new_config = %{
      id: :dynamic_agent,
      type: :specialist,
      actions: [Runtime.Action],
      signals: canonical_signals()
    }

    assert {:ok, pid} = Runtime.add_agent(runtime, new_config)
    assert is_pid(pid)
    assert Process.alive?(pid)

    agents = Runtime.list_agents(runtime)
    assert length(agents) == 1
    assert hd(agents).agent_id == :dynamic_agent

    assert {:ok, config} = Runtime.get_agent_config(runtime, :dynamic_agent)
    assert config.id == :dynamic_agent
  end

  test "add_agent returns error for duplicate agent", %{config_path: path, router: router} do
    write_config(path, [
      %{
        id: :existing_agent,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      }
    ])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)

    duplicate_config = %{
      id: :existing_agent,
      type: :specialist,
      actions: [Runtime.Action],
      signals: canonical_signals()
    }

    assert {:error, :agent_already_exists} = Runtime.add_agent(runtime, duplicate_config)
  end

  test "add_agent returns error for invalid config", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    invalid_config = %{
      id: :invalid_agent,
      type: :specialist
      # Missing required signals
    }

    assert {:error, _validation_error} = Runtime.add_agent(runtime, invalid_config)
  end

  test "remove_agent dynamically removes an agent", %{config_path: path, router: router} do
    write_config(path, [
      %{
        id: :removable_agent,
        type: :specialist,
        actions: [Runtime.Action],
        signals: canonical_signals()
      }
    ])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)

    assert :ok = Runtime.remove_agent(runtime, :removable_agent)

    assert eventually(fn -> Runtime.list_agents(runtime) == [] end)

    assert {:error, :not_found} = Runtime.get_agent_config(runtime, :removable_agent)
  end

  test "remove_agent returns error for non-existent agent", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert {:error, :not_found} = Runtime.remove_agent(runtime, :nonexistent)
  end

  test "add_agent and remove_agent work together", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    # Add an agent
    config = %{
      id: :temporary_agent,
      type: :specialist,
      actions: [Runtime.Action],
      signals: canonical_signals()
    }

    assert {:ok, _pid} = Runtime.add_agent(runtime, config)
    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)

    # Remove the agent
    assert :ok = Runtime.remove_agent(runtime, :temporary_agent)
    assert eventually(fn -> Runtime.list_agents(runtime) == [] end)

    # Add it again
    assert {:ok, _pid} = Runtime.add_agent(runtime, config)
    assert eventually(fn -> Runtime.list_agents(runtime) |> length() == 1 end)
  end

  test "list_skills returns all available skills", %{
    config_path: path,
    skills_dir: skills_dir,
    router: router
  } do
    write_config(path, [])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path,
         reconcile_interval: 50,
         skill_directories: [skills_dir],
         router: router}
      )

    skills = Runtime.list_skills(runtime)
    assert is_list(skills)
    assert length(skills) == 1

    skill = hd(skills)
    assert skill.id == "demo-skill"
    assert skill.name == "demo-skill"
    assert skill.description == "Demo instructions"
    assert skill.body_loaded? == false
  end

  test "list_skills returns error when no registry", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert {:error, :no_registry} = Runtime.list_skills(runtime)
  end

  test "get_skill returns skill metadata", %{
    config_path: path,
    skills_dir: skills_dir,
    router: router
  } do
    write_config(path, [])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path,
         reconcile_interval: 50,
         skill_directories: [skills_dir],
         router: router}
      )

    assert {:ok, skill} = Runtime.get_skill(runtime, "demo-skill")
    assert skill.id == "demo-skill"
    assert skill.name == "demo-skill"
    assert skill.body_loaded? == false
    assert skill.body == nil
  end

  test "get_skill returns error for non-existent skill", %{
    config_path: path,
    skills_dir: skills_dir,
    router: router
  } do
    write_config(path, [])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path,
         reconcile_interval: 50,
         skill_directories: [skills_dir],
         router: router}
      )

    assert :error = Runtime.get_skill(runtime, "nonexistent-skill")
  end

  test "get_skill returns error when no registry", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert {:error, :no_registry} = Runtime.get_skill(runtime, "any-skill")
  end

  test "load_skill_body loads full skill content", %{
    config_path: path,
    skills_dir: skills_dir,
    router: router
  } do
    write_config(path, [])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path,
         reconcile_interval: 50,
         skill_directories: [skills_dir],
         router: router}
      )

    assert {:ok, skill} = Runtime.load_skill_body(runtime, "demo-skill")
    assert skill.id == "demo-skill"
    assert skill.body_loaded? == true
    assert skill.body =~ "## Usage"
    assert skill.body =~ "Step-by-step guide"
  end

  test "load_skill_body returns error for non-existent skill", %{
    config_path: path,
    skills_dir: skills_dir,
    router: router
  } do
    write_config(path, [])

    runtime =
      start_supervised!(
        {Runtime,
         config_source: path,
         reconcile_interval: 50,
         skill_directories: [skills_dir],
         router: router}
      )

    assert {:error, :not_found} = Runtime.load_skill_body(runtime, "nonexistent-skill")
  end

  test "load_skill_body returns error when no registry", %{config_path: path, router: router} do
    write_config(path, [])

    runtime =
      start_supervised!({Runtime, config_source: path, reconcile_interval: 50, router: router})

    assert {:error, :no_registry} = Runtime.load_skill_body(runtime, "any-skill")
  end

  defp canonical_signals do
    %{subscribes: [:review_request], emits: [:review_result]}
  end

  defp write_config(path, data) do
    contents =
      data
      |> inspect(limit: :infinity, pretty: true, width: 80)
      |> Kernel.<>("\n")

    File.write!(path, contents)
  end

  defp eventually(fun), do: eventually(fun, 20)

  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, retries) do
    if fun.() do
      true
    else
      Process.sleep(50)
      eventually(fun, retries - 1)
    end
  end
end

defmodule Synapse.Orchestrator.RuntimeTest.TestOrchestration do
  def classify(_review), do: %{path: :fast_path, rationale: ""}
  def aggregate(_results, _state), do: %{}
  def fast_path(_signal, _router), do: :ok
end
