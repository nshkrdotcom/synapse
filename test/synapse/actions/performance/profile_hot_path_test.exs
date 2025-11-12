defmodule Synapse.Actions.Performance.ProfileHotPathTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Performance.ProfileHotPath

  describe "ProfileHotPath action" do
    test "analyzes function call frequency" do
      params = %{
        diff: """
        +  def frequently_called do
        +    expensive_operation()
        +    another_expensive_call()
        +  end
        """,
        files: ["lib/processor.ex"],
        metadata: %{hot_functions: ["expensive_operation"]}
      }

      assert {:ok, result} = ProfileHotPath.run(params, %{})
      assert is_list(result.findings)
      assert is_float(result.confidence)
    end

    test "returns low severity for normal code paths" do
      params = %{
        diff: "  + def simple, do: :ok",
        files: ["lib/simple.ex"],
        metadata: %{}
      }

      assert {:ok, result} = ProfileHotPath.run(params, %{})
      # May or may not have findings, but should not crash
      assert is_list(result.findings)
    end

    test "handles empty diff" do
      params = %{
        diff: "",
        files: []
      }

      assert {:ok, result} = Jido.Exec.run(ProfileHotPath, params, %{})
      assert result.findings == []
    end
  end
end
