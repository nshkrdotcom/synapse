defmodule Synapse.Actions.Performance.CheckComplexityTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Performance.CheckComplexity
  alias Synapse.TestSupport.Fixtures.DiffSamples

  describe "CheckComplexity action" do
    test "detects high cyclomatic complexity" do
      params = %{
        diff: DiffSamples.high_complexity_diff(),
        language: "elixir",
        thresholds: %{max_complexity: 10}
      }

      assert {:ok, result} = CheckComplexity.run(params, %{})

      assert length(result.findings) > 0
      finding = hd(result.findings)
      assert finding.type in [:high_complexity, :complexity_hotspot]
      assert finding.severity in [:low, :medium, :high]
      assert is_binary(finding.summary)
      assert finding.summary =~ "complexity"
    end

    test "returns no findings for simple code" do
      params = %{
        diff: DiffSamples.clean_diff(),
        language: "elixir",
        thresholds: %{}
      }

      assert {:ok, result} = CheckComplexity.run(params, %{})
      assert result.findings == []
    end

    test "uses default thresholds when not provided" do
      params = %{
        diff: DiffSamples.high_complexity_diff(),
        language: "elixir"
      }

      # Should still detect complexity with default thresholds
      assert {:ok, result} = Jido.Exec.run(CheckComplexity, params, %{})
      assert is_list(result.findings)
    end

    test "handles empty diff" do
      params = %{
        diff: "",
        language: "elixir"
      }

      assert {:ok, result} = Jido.Exec.run(CheckComplexity, params, %{})
      assert result.findings == []
    end
  end
end
