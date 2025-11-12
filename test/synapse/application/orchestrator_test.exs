defmodule Synapse.Application.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Synapse.Application.Orchestrator

  describe "child_spec/2" do
    test "returns nil when orchestrator runtime disabled" do
      assert Orchestrator.child_spec([enabled: false], Synapse.Runtime) == nil
    end

    test "builds a child spec and starts runtime when enabled" do
      config_file = tmp_config([])
      unique = System.unique_integer([:positive])
      runtime_name = Synapse.Runtime

      spec =
        Orchestrator.child_spec(
          [
            enabled: true,
            name: :"orch_child_#{unique}",
            config_source: config_file,
            reconcile_interval: 25
          ],
          runtime_name
        )

      assert %{start: {Synapse.Application.Orchestrator, :start_link, _}} = spec

      {:ok, pid} = start_supervised(spec)
      assert Synapse.Orchestrator.Runtime.list_agents(pid) == []
    end
  end

  defp tmp_config(content) do
    tmp =
      System.tmp_dir!()
      |> Path.join("orch_config_#{System.unique_integer([:positive])}.exs")

    File.write!(tmp, """
    #{inspect(content, limit: :infinity)}
    """)

    tmp
  end
end
