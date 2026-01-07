defmodule Synapse.Actions.Review.GenerateSummaryTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Review.GenerateSummary
  alias Synapse.TestSupport.Factory

  describe "GenerateSummary action" do
    test "generates summary from specialist findings" do
      security_findings = [
        Factory.build_finding(type: :sql_injection, severity: :high, file: "lib/repo.ex"),
        Factory.build_finding(type: :xss, severity: :medium, file: "lib/web/template.ex")
      ]

      performance_findings = [
        Factory.build_finding(
          type: :high_complexity,
          severity: :low,
          file: "lib/processor.ex"
        )
      ]

      params = %{
        review_id: "review_123",
        findings: security_findings ++ performance_findings,
        metadata: %{
          decision_path: :deep_review,
          specialists_resolved: ["security_specialist", "performance_specialist"],
          duration_ms: 1500
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})

      assert result.review_id == "review_123"
      assert result.status == :complete
      assert result.severity == :high
      # Overall severity should be max of all findings
      assert Enum.count(result.findings) == 3
      assert is_list(result.recommendations)
      assert is_list(result.escalations)
      assert result.metadata.decision_path == :deep_review
    end

    test "sets status to failed when no specialists resolved" do
      params = %{
        review_id: "review_456",
        findings: [],
        metadata: %{
          decision_path: :deep_review,
          specialists_resolved: [],
          duration_ms: 500
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})
      assert result.status == :failed
      assert result.escalations != []
      assert hd(result.escalations) =~ "No specialists"
    end

    test "calculates severity as max of all findings" do
      findings = [
        Factory.build_finding(severity: :low),
        Factory.build_finding(severity: :medium),
        Factory.build_finding(severity: :high),
        Factory.build_finding(severity: :low)
      ]

      params = %{
        review_id: "review_789",
        findings: findings,
        metadata: %{
          decision_path: :deep_review,
          specialists_resolved: ["security_specialist"],
          duration_ms: 800
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})
      assert result.severity == :high
    end

    test "sets severity to none when no findings" do
      params = %{
        review_id: "review_clean",
        findings: [],
        metadata: %{
          decision_path: :fast_path,
          specialists_resolved: ["security_specialist"],
          duration_ms: 200
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})
      assert result.severity == :none
      assert result.status == :complete
    end

    test "sorts findings by severity (high to low)" do
      findings = [
        Factory.build_finding(severity: :low, type: :style),
        Factory.build_finding(severity: :high, type: :security),
        Factory.build_finding(severity: :medium, type: :performance)
      ]

      params = %{
        review_id: "review_sorted",
        findings: findings,
        metadata: %{
          decision_path: :deep_review,
          specialists_resolved: ["security_specialist"],
          duration_ms: 300
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})

      assert [
               %{severity: :high},
               %{severity: :medium},
               %{severity: :low}
             ] = result.findings
    end

    test "generates recommendations from high-severity findings" do
      findings = [
        Factory.build_finding(
          type: :sql_injection,
          severity: :high,
          file: "lib/repo.ex",
          recommendation: "Use parameterized queries"
        ),
        Factory.build_finding(
          type: :xss,
          severity: :high,
          file: "lib/template.ex",
          recommendation: "Escape user input"
        )
      ]

      params = %{
        review_id: "review_recs",
        findings: findings,
        metadata: %{
          decision_path: :deep_review,
          specialists_resolved: ["security_specialist"],
          duration_ms: 400
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})
      assert Enum.count(result.recommendations) == 2
      assert "Use parameterized queries" in result.recommendations
      assert "Escape user input" in result.recommendations
    end

    test "adds escalations for critical findings requiring human review" do
      findings = [
        Factory.build_finding(
          type: :auth_bypass,
          severity: :high,
          file: "lib/auth.ex",
          summary: "Authentication bypass detected"
        )
      ]

      params = %{
        review_id: "review_critical",
        findings: findings,
        metadata: %{
          decision_path: :deep_review,
          specialists_resolved: ["security_specialist"],
          duration_ms: 600
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})
      # High severity findings should trigger escalation
      assert result.escalations != []
    end

    test "returns validation error for missing review_id" do
      params = %{
        findings: [],
        metadata: %{
          decision_path: :fast_path,
          specialists_resolved: [],
          duration_ms: 100
        }
      }

      # Use Jido.Exec.run to trigger schema validation
      assert {:error, error} = Jido.Exec.run(GenerateSummary, params, %{})
      assert is_exception(error)
    end

    test "returns validation error for invalid metadata" do
      params = %{
        review_id: "review_bad",
        findings: [],
        metadata: "not a map"
      }

      # Use Jido.Exec.run to trigger schema validation
      assert {:error, error} = Jido.Exec.run(GenerateSummary, params, %{})
      assert is_exception(error)
    end

    test "preserves metadata fields in result" do
      params = %{
        review_id: "review_meta",
        findings: [],
        metadata: %{
          decision_path: :fast_path,
          specialists_resolved: ["security_specialist", "performance_specialist"],
          duration_ms: 750
        }
      }

      assert {:ok, result} = GenerateSummary.run(params, %{})
      assert result.metadata.decision_path == :fast_path

      assert result.metadata.specialists_resolved == [
               "security_specialist",
               "performance_specialist"
             ]

      assert result.metadata.duration_ms == 750
    end
  end
end
