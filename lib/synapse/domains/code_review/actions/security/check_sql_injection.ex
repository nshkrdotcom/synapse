defmodule Synapse.Domains.CodeReview.Actions.CheckSQLInjection do
  @moduledoc """
  Detects potential SQL injection vulnerabilities in code diffs.

  Analyzes diffs for patterns indicating SQL injection risks:
  - String interpolation in SQL queries
  - Unparameterized query construction
  - Direct user input in SQL strings
  - Missing prepared statement usage

  Returns findings with severity ratings and remediation recommendations.
  """

  use Jido.Action,
    name: "check_sql_injection",
    description: "Analyzes diffs for SQL injection vulnerabilities",
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
        doc: "Additional context (language, framework, etc.)"
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
        generate_recommendations(findings)
      else
        []
      end

    result = %{
      findings: findings,
      confidence: confidence,
      recommended_actions: recommended_actions
    }

    Logger.debug("SQL injection check completed",
      findings_count: findings_count,
      confidence: confidence,
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
      String.starts_with?(String.trim_leading(line), "+")
    end)
    |> Enum.flat_map(fn {line, idx} ->
      detect_sql_injection_in_line(line, idx, files)
    end)
    |> Enum.uniq_by(&{&1.type, &1.file, &1.summary})
  end

  defp detect_sql_injection_in_line(line, _idx, files) do
    patterns = sql_injection_patterns()

    matches =
      Enum.filter(patterns, fn pattern ->
        Regex.match?(pattern, line)
      end)

    if matches != [] do
      file = determine_file_from_line(line, files)

      [
        %{
          type: :sql_injection,
          severity: :high,
          file: file,
          summary:
            "Potential SQL injection: String interpolation or concatenation detected in SQL query",
          recommendation:
            "Use parameterized queries or prepared statements to prevent SQL injection"
        }
      ]
    else
      []
    end
  end

  defp determine_file_from_line(_line, []), do: "unknown"
  defp determine_file_from_line(_line, [file | _]), do: file

  defp calculate_confidence("", []), do: 1.0
  defp calculate_confidence(_diff, []), do: 0.9
  defp calculate_confidence(_diff, findings) when findings != [], do: 0.85

  defp generate_recommendations(findings) do
    findings
    |> Enum.map(& &1.recommendation)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
  end

  defp sql_injection_patterns do
    [
      ~r/["']SELECT\s+.*\#{.*}.*["']/i,
      ~r/["']INSERT\s+.*\#{.*}.*["']/i,
      ~r/["']UPDATE\s+.*\#{.*}.*["']/i,
      ~r/["']DELETE\s+.*\#{.*}.*["']/i,
      ~r/["'](SELECT|INSERT|UPDATE|DELETE|FROM|WHERE).*\#{/i,
      ~r/WHERE\s+.*=\s*["'].*\#{/i,
      ~r/["']SELECT\s+.*["']\s*\+/i
    ]
  end
end
