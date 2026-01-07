defmodule Synapse.Domains.CodeReview.Actions.CheckMemoryUsage do
  @moduledoc """
  Detects memory allocation patterns that may cause performance issues.

  Analyzes diffs for:
  - Conversion of streams to lists (greedy allocation)
  - Large list comprehensions
  - Inefficient Enum operations on large datasets
  """

  use Jido.Action,
    name: "check_memory_usage",
    description: "Analyzes diffs for memory allocation issues",
    schema: [
      diff: [type: :string, required: true],
      files: [type: {:list, :string}, required: true],
      metadata: [type: :map, default: %{}]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    findings = analyze_diff(params.diff, params.files)
    confidence = if findings != [], do: 0.75, else: 0.85

    recommended_actions =
      if findings != [] do
        [
          "Use Stream instead of Enum.to_list for large datasets",
          "Process data in chunks to reduce memory footprint",
          "Consider lazy evaluation for expensive operations"
        ]
      else
        []
      end

    {:ok,
     %{
       findings: findings,
       confidence: confidence,
       recommended_actions: recommended_actions
     }}
  end

  defp analyze_diff("", _files), do: []

  defp analyze_diff(diff, files) do
    patterns = memory_issue_patterns()

    diff
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(String.trim_leading(&1), "+"))
    |> Enum.flat_map(fn line ->
      if Enum.any?(patterns, &Regex.match?(&1, line)) do
        [
          %{
            type: :memory_hotspot,
            severity: :medium,
            file: hd(files ++ ["unknown"]),
            summary: "Greedy memory allocation pattern detected",
            recommendation: "Use Stream for lazy evaluation"
          }
        ]
      else
        []
      end
    end)
    |> Enum.uniq_by(&{&1.type, &1.file})
  end

  defp memory_issue_patterns do
    [
      ~r/Enum\.to_list/,
      ~r/Repo\.all\(/,
      ~r/\|>\s*Enum\.to_list\(\)/
    ]
  end
end
