defmodule Synapse.Actions.Security.CheckXSSTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Security.CheckXSS
  alias Synapse.TestSupport.Fixtures.DiffSamples

  describe "CheckXSS action" do
    test "detects XSS vulnerabilities in diff" do
      params = %{
        diff: DiffSamples.xss_diff(),
        files: ["lib/web/templates/user/show.html.heex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckXSS.run(params, %{})

      assert length(result.findings) > 0
      finding = hd(result.findings)
      assert finding.type == :xss
      assert finding.severity in [:high, :medium]
      assert is_binary(finding.summary)
      assert finding.summary =~ ~r/raw|escape|XSS/i
    end

    test "returns no findings for clean diff" do
      params = %{
        diff: DiffSamples.clean_diff(),
        files: ["lib/calculator.ex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckXSS.run(params, %{})
      assert result.findings == []
    end

    test "provides remediation recommendations" do
      params = %{
        diff: DiffSamples.xss_diff(),
        files: ["lib/web/templates/user/show.html.heex"],
        metadata: %{}
      }

      assert {:ok, result} = CheckXSS.run(params, %{})
      assert length(result.recommended_actions) > 0
      assert hd(result.recommended_actions) =~ ~r/escap|sanitiz|raw/i
    end

    test "handles empty diff" do
      params = %{
        diff: "",
        files: [],
        metadata: %{}
      }

      assert {:ok, result} = CheckXSS.run(params, %{})
      assert result.findings == []
      assert result.confidence == 1.0
    end
  end
end
