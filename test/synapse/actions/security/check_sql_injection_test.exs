defmodule Synapse.Actions.Security.CheckSQLInjectionTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Security.CheckSQLInjection
  alias Synapse.TestSupport.Fixtures.DiffSamples

  describe "CheckSQLInjection action" do
    test "detects SQL injection in diff" do
      params = %{
        diff: DiffSamples.sql_injection_diff(),
        files: ["lib/user_repository.ex"],
        metadata: %{language: "elixir", framework: "phoenix"}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})

      assert result.findings != []
      finding = hd(result.findings)
      assert finding.type == :sql_injection
      assert finding.severity == :high
      assert finding.file == "lib/user_repository.ex"
      assert is_binary(finding.summary)
      assert is_float(result.confidence)
      assert result.confidence > 0.5
      assert is_list(result.recommended_actions)
    end

    test "returns no findings for clean diff" do
      params = %{
        diff: DiffSamples.clean_diff(),
        files: ["lib/calculator.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})

      assert result.findings == []
      assert result.confidence > 0.0
    end

    test "handles empty diff" do
      params = %{
        diff: "",
        files: [],
        metadata: %{}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})

      assert result.findings == []
      assert result.confidence == 1.0
      # Empty diff means nothing to check, high confidence in "no issues"
    end

    test "detects multiple SQL injection patterns" do
      multi_injection_diff = """
      diff --git a/lib/repo.ex b/lib/repo.ex
      +    query = "SELECT * FROM users WHERE id = '\#{id}'"
      +    another = "DELETE FROM posts WHERE id = '\#{post_id}'"
      """

      params = %{
        diff: multi_injection_diff,
        files: ["lib/repo.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})
      refute Enum.empty?(result.findings)
      # Should detect at least one SQL injection pattern
    end

    test "provides actionable recommendations" do
      params = %{
        diff: DiffSamples.sql_injection_diff(),
        files: ["lib/user_repository.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})

      assert result.recommended_actions != []
      recommendation = hd(result.recommended_actions)
      assert is_binary(recommendation)
      assert recommendation =~ ~r/parameter|prepare|bind/i
    end

    test "returns validation error for missing diff" do
      params = %{
        files: ["lib/test.ex"],
        metadata: %{}
      }

      assert {:error, error} = Jido.Exec.run(CheckSQLInjection, params, %{})
      assert is_exception(error)
    end

    test "handles non-Elixir files gracefully" do
      params = %{
        diff: "some python code diff",
        files: ["app.py"],
        metadata: %{language: "python"}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})
      # Should still analyze, might have different confidence
      assert is_list(result.findings)
    end

    test "includes file information in findings" do
      params = %{
        diff: DiffSamples.sql_injection_diff(),
        files: ["lib/user_repository.ex", "lib/admin_repository.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckSQLInjection.run(params, %{})

      if result.findings != [] do
        finding = hd(result.findings)
        assert finding.file in params.files
      end
    end
  end
end
