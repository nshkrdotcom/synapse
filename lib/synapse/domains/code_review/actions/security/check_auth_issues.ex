defmodule Synapse.Domains.CodeReview.Actions.CheckAuthIssues do
  @moduledoc """
  Detects authentication and authorization issues in code diffs.

  Analyzes diffs for patterns indicating auth/authz risks:
  - Removed authentication plugs or guards
  - Bypassed authorization checks
  - Weakened permission requirements
  - Missing access control

  Returns findings with severity ratings and remediation recommendations.
  """

  use Jido.Action,
    name: "check_auth_issues",
    description: "Analyzes diffs for authentication and authorization vulnerabilities",
    schema: [
      diff: [
        type: :string,
        required: true,
        doc: "Unified diff content to analyze"
      ],
      files: [
        type: {:list, :string},
        required: true,
        doc: "List of files modified in the diff"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Additional context"
      ]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    findings = analyze_diff(params.diff, params.files)
    confidence = calculate_confidence(params.diff, findings)
    findings_count = Enum.count(findings)

    recommended_actions =
      if findings != [] do
        [
          "Restore removed authentication guards",
          "Ensure authorization checks are in place",
          "Review access control requirements for affected endpoints"
        ]
      else
        []
      end

    result = %{
      findings: findings,
      confidence: confidence,
      recommended_actions: recommended_actions
    }

    Logger.debug("Auth issues check completed",
      findings_count: findings_count,
      files: params.files
    )

    {:ok, result}
  end

  defp analyze_diff("", _files), do: []

  defp analyze_diff(diff, files) do
    lines = String.split(diff, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, _idx} ->
      String.starts_with?(String.trim_leading(line), "-")
    end)
    |> Enum.flat_map(fn {line, idx} ->
      detect_auth_issue_in_line(line, idx, files)
    end)
    |> Enum.uniq_by(&{&1.type, &1.file})
  end

  defp detect_auth_issue_in_line(line, _idx, files) do
    patterns = auth_issue_patterns()

    has_auth_issue? =
      Enum.any?(patterns, fn pattern ->
        Regex.match?(pattern, line)
      end)

    if has_auth_issue? do
      file = determine_file(files)

      [
        %{
          type: :auth_bypass,
          severity: :high,
          file: file,
          summary: "Authentication or authorization control removed - potential security bypass",
          recommendation: "Restore removed authentication guards"
        }
      ]
    else
      []
    end
  end

  defp determine_file([]), do: "unknown"
  defp determine_file([file | _]), do: file

  defp calculate_confidence("", []), do: 1.0
  defp calculate_confidence(_diff, []), do: 0.9
  defp calculate_confidence(_diff, _findings), do: 0.85

  defp auth_issue_patterns do
    [
      ~r/plug\s+:require_auth/i,
      ~r/plug\s+:require_admin/i,
      ~r/plug\s+:authenticate/i,
      ~r/authorize/i,
      ~r/can\?/i,
      ~r/has_permission/i,
      ~r/when\s+.*is_admin/i
    ]
  end
end
