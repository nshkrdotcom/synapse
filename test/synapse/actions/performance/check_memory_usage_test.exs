defmodule Synapse.Actions.Performance.CheckMemoryUsageTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Performance.CheckMemoryUsage
  alias Synapse.TestSupport.Fixtures.DiffSamples

  describe "CheckMemoryUsage action" do
    test "detects greedy memory allocation patterns" do
      params = %{
        diff: DiffSamples.memory_issue_diff(),
        files: ["lib/data_loader.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckMemoryUsage.run(params, %{})
      assert result.findings != []
      finding = hd(result.findings)
      assert finding.type in [:memory_hotspot, :greedy_allocation]
      assert finding.severity in [:medium, :high]
    end

    test "returns no findings for stream-based code" do
      params = %{
        diff: DiffSamples.clean_diff(),
        files: ["lib/calculator.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckMemoryUsage.run(params, %{})
      assert result.findings == []
    end

    test "handles empty diff" do
      params = %{
        diff: "",
        files: []
      }

      assert {:ok, result} = Jido.Exec.run(CheckMemoryUsage, params, %{})
      assert result.findings == []
    end
  end
end
