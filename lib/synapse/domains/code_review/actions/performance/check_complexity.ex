defmodule Synapse.Domains.CodeReview.Actions.CheckComplexity do
  @moduledoc """
  Analyzes code diffs for high cyclomatic complexity.

  Detects functions with excessive conditional branches (cond, case, if/else)
  that may indicate maintainability issues or performance hotspots.

  Returns findings with complexity scores and refactoring recommendations.
  """

  use Jido.Action,
    name: "check_complexity",
    description: "Analyzes diffs for high cyclomatic complexity",
    schema: [
      diff: [
        type: :string,
        required: true,
        doc: "Unified diff content to analyze"
      ],
      files: [
        type: {:list, :string},
        default: ["unknown"],
        doc: "List of files being analyzed"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Additional metadata for analysis"
      ],
      language: [
        type: :string,
        default: "elixir",
        doc: "Programming language of the code"
      ],
      thresholds: [
        type: :map,
        default: %{},
        doc: "Complexity thresholds (default: max_complexity: 10)"
      ]
    ]

  require Logger

  @default_max_complexity 10

  @impl true
  def on_before_validate_params(params) do
    default_thresholds = %{max_complexity: @default_max_complexity}

    params_with_defaults =
      Map.update(params, :thresholds, default_thresholds, fn thresholds ->
        Map.merge(default_thresholds, thresholds)
      end)

    {:ok, params_with_defaults}
  end

  @impl true
  def run(params, _context) do
    files = Map.get(params, :files, ["unknown"])
    findings = analyze_diff(params.diff, params.thresholds, files)
    confidence = calculate_confidence(params.diff, findings)
    findings_count = Enum.count(findings)

    recommended_actions =
      if findings != [] do
        [
          "Refactor complex functions into smaller, focused units",
          "Consider using pattern matching instead of nested conditionals",
          "Extract complex logic into separate helper functions"
        ]
      else
        []
      end

    result = %{
      findings: findings,
      confidence: confidence,
      recommended_actions: recommended_actions
    }

    Logger.debug("Complexity check completed",
      findings_count: findings_count,
      language: params.language
    )

    {:ok, result}
  end

  defp analyze_diff("", _thresholds, _files), do: []

  defp analyze_diff(diff, thresholds, files) do
    max_complexity = Map.get(thresholds, :max_complexity, @default_max_complexity)

    added_lines =
      diff
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(String.trim_leading(&1), "+"))
      |> Enum.join("\n")

    complexity = estimate_complexity(added_lines)

    if complexity > max_complexity do
      [
        %{
          type: :high_complexity,
          severity: determine_severity(complexity, max_complexity),
          file: hd(files ++ ["unknown"]),
          summary:
            "High cyclomatic complexity detected (estimated: #{complexity}, threshold: #{max_complexity})",
          recommendation: "Refactor complex functions into smaller units"
        }
      ]
    else
      []
    end
  end

  defp estimate_complexity(code) do
    cond_branches = length(Regex.scan(~r/cond\s+do/i, code))
    case_clauses = length(Regex.scan(~r/case\s+/i, code))
    if_statements = length(Regex.scan(~r/\bif\s+/i, code))
    when_guards = length(Regex.scan(~r/when\s+/i, code))
    cond_conditions = length(Regex.scan(~r/->/, code))

    base = 1

    base + cond_branches * 2 + cond_conditions + case_clauses + if_statements + when_guards
  end

  defp determine_severity(complexity, threshold) do
    cond do
      complexity > threshold * 2 -> :high
      complexity > threshold * 1.5 -> :medium
      true -> :low
    end
  end

  defp calculate_confidence("", []), do: 1.0
  defp calculate_confidence(_diff, []), do: 0.85
  defp calculate_confidence(_diff, _findings), do: 0.7
end
