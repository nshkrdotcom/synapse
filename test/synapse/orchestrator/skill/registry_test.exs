defmodule Synapse.Orchestrator.Skill.RegistryTest do
  use ExUnit.Case, async: true

  alias Synapse.Orchestrator.Skill.Registry

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "synapse_skill_registry_#{System.unique_integer([:positive])}")

    skills_dir = Path.join(tmp_dir, "skills")
    skill_path = Path.join(skills_dir, "demo-skill")
    File.mkdir_p!(skill_path)

    File.write!(
      Path.join(skill_path, "SKILL.md"),
      """
      ---
      name: demo-skill
      description: Demo instructions
      allowed-tools:
        - Read
        - Bash
      ---
      ## Usage

      Step-by-step guide.
      """
    )

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{skills_dir: skills_dir}
  end

  test "discovers skills and loads body on demand", %{skills_dir: skills_dir} do
    {:ok, registry} = Registry.start_link(directories: [skills_dir])

    [skill] = Registry.list(registry)
    assert skill.id == "demo-skill"
    assert Enum.sort(skill.allowed_tools) == ["Bash", "Read"]
    refute skill.body_loaded?

    assert {:ok, loaded} = Registry.load_body(registry, "demo-skill")
    assert loaded.body_loaded?
    assert loaded.body =~ "Step-by-step"

    summary = Registry.metadata_summary(registry)
    assert summary =~ "demo-skill"
  end
end
