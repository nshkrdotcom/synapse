defmodule Synapse.TestSupport.Factory do
  @moduledoc """
  Factory helpers for generating test data.
  Provides deterministic data generation for review requests,
  signals, and other test entities.
  """

  @doc """
  Generates a review request signal payload.

  ## Options
    * `:review_id` - Custom review ID (defaults to generated)
    * `:diff` - Custom diff content (defaults to clean diff)
    * `:files_changed` - Number of files changed
    * `:labels` - List of labels/tags
    * `:intent` - Review intent (e.g., "feature", "hotfix")
    * `:risk_factor` - Risk score 0.0-1.0
    * `:metadata` - Additional metadata

  ## Examples

      payload = build_review_request()
      payload = build_review_request(labels: ["security"], intent: "hotfix")
  """
  def build_review_request(opts \\ []) do
    review_id = Keyword.get(opts, :review_id, "review_#{:rand.uniform(100_000)}")
    diff = Keyword.get(opts, :diff, Synapse.TestSupport.Fixtures.DiffSamples.clean_diff())
    files_changed = Keyword.get(opts, :files_changed, 3)
    labels = Keyword.get(opts, :labels, [])
    intent = Keyword.get(opts, :intent, "feature")
    risk_factor = Keyword.get(opts, :risk_factor, 0.0)

    metadata =
      Keyword.get(opts, :metadata, %{
        author: "test_author",
        branch: "feature/test",
        repo: "test/repo",
        timestamp: deterministic_timestamp()
      })

    %{
      review_id: review_id,
      diff: diff,
      files_changed: files_changed,
      labels: labels,
      intent: intent,
      risk_factor: risk_factor,
      metadata: metadata
    }
  end

  @doc """
  Generates a review result payload (specialist output).

  ## Options
    * `:review_id` - Review ID to correlate
    * `:agent` - Agent name ("security_specialist" or "performance_specialist")
    * `:confidence` - Confidence score 0.0-1.0
    * `:findings` - List of findings
    * `:should_escalate` - Boolean
    * `:runtime_ms` - Runtime in milliseconds

  ## Examples

      result = build_review_result(agent: "security_specialist")
      result = build_review_result(findings: [finding], should_escalate: true)
  """
  def build_review_result(opts \\ []) do
    review_id = Keyword.get(opts, :review_id, "review_#{:rand.uniform(100_000)}")
    agent = Keyword.get(opts, :agent, "security_specialist")
    confidence = Keyword.get(opts, :confidence, 0.85)
    findings = Keyword.get(opts, :findings, [])
    should_escalate = Keyword.get(opts, :should_escalate, false)
    runtime_ms = Keyword.get(opts, :runtime_ms, 150)

    %{
      review_id: review_id,
      agent: agent,
      confidence: confidence,
      findings: findings,
      should_escalate: should_escalate,
      metadata: %{
        runtime_ms: runtime_ms,
        path: :deep_review,
        actions_run: []
      }
    }
  end

  @doc """
  Generates a finding map.

  ## Options
    * `:type` - Finding type atom (e.g., :sql_injection, :xss)
    * `:severity` - :none, :low, :medium, or :high
    * `:file` - File path
    * `:summary` - Finding description
    * `:recommendation` - Remediation suggestion

  ## Examples

      finding = build_finding(type: :sql_injection, severity: :high)
  """
  def build_finding(opts \\ []) do
    type = Keyword.get(opts, :type, :code_smell)
    severity = Keyword.get(opts, :severity, :low)
    file = Keyword.get(opts, :file, "lib/example.ex")
    summary = Keyword.get(opts, :summary, "Example finding")
    recommendation = Keyword.get(opts, :recommendation)

    %{
      type: type,
      severity: severity,
      file: file,
      summary: summary,
      recommendation: recommendation
    }
  end

  @doc """
  Generates a review summary payload (coordinator output).

  ## Options
    * `:review_id` - Review ID
    * `:status` - :complete or :failed
    * `:severity` - Overall severity
    * `:findings` - List of findings
    * `:recommendations` - List of recommendations
    * `:escalations` - List of escalation messages
    * `:decision_path` - :fast_path or :deep_review
    * `:specialists_resolved` - List of specialist names
    * `:duration_ms` - Total duration

  ## Examples

      summary = build_review_summary(status: :complete, severity: :high)
  """
  def build_review_summary(opts \\ []) do
    review_id = Keyword.get(opts, :review_id, "review_#{:rand.uniform(100_000)}")
    status = Keyword.get(opts, :status, :complete)
    severity = Keyword.get(opts, :severity, :none)
    findings = Keyword.get(opts, :findings, [])
    recommendations = Keyword.get(opts, :recommendations, [])
    escalations = Keyword.get(opts, :escalations, [])

    metadata = %{
      decision_path: Keyword.get(opts, :decision_path, :deep_review),
      specialists_resolved: Keyword.get(opts, :specialists_resolved, []),
      duration_ms: Keyword.get(opts, :duration_ms, 500)
    }

    %{
      review_id: review_id,
      status: status,
      severity: severity,
      findings: findings,
      recommendations: recommendations,
      escalations: escalations,
      metadata: metadata
    }
  end

  @doc """
  Returns a deterministic timestamp for testing.
  """
  def deterministic_timestamp do
    DateTime.from_unix!(1_707_667_200, :second)
  end
end
