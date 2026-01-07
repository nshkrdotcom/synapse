defmodule Synapse.Actions.Security.CheckAuthIssuesTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Security.CheckAuthIssues
  alias Synapse.TestSupport.Fixtures.DiffSamples

  describe "CheckAuthIssues action" do
    test "detects removed authentication guards" do
      params = %{
        diff: DiffSamples.auth_issue_diff(),
        files: ["lib/web/controllers/admin_controller.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckAuthIssues.run(params, %{})

      assert result.findings != []
      finding = hd(result.findings)
      assert finding.type == :auth_bypass
      assert finding.severity == :high
      assert finding.summary =~ ~r/authentication|authorization|guard|plug/i
    end

    test "returns no findings for clean diff" do
      params = %{
        diff: DiffSamples.clean_diff(),
        files: ["lib/calculator.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckAuthIssues.run(params, %{})
      assert result.findings == []
    end

    test "provides security remediation recommendations" do
      params = %{
        diff: DiffSamples.auth_issue_diff(),
        files: ["lib/web/controllers/admin_controller.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckAuthIssues.run(params, %{})
      assert result.recommended_actions != []
      assert hd(result.recommended_actions) =~ ~r/authentication|authorization|guard/i
    end

    test "handles empty diff" do
      params = %{
        diff: "",
        files: [],
        metadata: %{}
      }

      assert {:ok, result} = CheckAuthIssues.run(params, %{})
      assert result.findings == []
      assert result.confidence == 1.0
    end
  end
end
