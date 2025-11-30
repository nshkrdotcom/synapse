defmodule Synapse.Domains.CodeReview.Actions.ProfileHotPath do
  @moduledoc """
  Profiles potential hot paths in code changes.

  Identifies frequently called functions or code paths that may benefit
  from optimization. Uses heuristics and metadata hints to estimate
  execution frequency.
  """

  use Jido.Action,
    name: "profile_hot_path",
    description: "Identifies potential performance hotspots in changes",
    schema: [
      diff: [type: :string, required: true],
      files: [type: {:list, :string}, required: true],
      metadata: [type: :map, default: %{}]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    hot_functions = Map.get(params.metadata, :hot_functions, [])
    findings = analyze_diff(params.diff, params.files, hot_functions)

    confidence = 0.7

    recommended_actions =
      if length(findings) > 0 do
        [
          "Profile actual execution to confirm hotspot",
          "Consider caching frequently called operations",
          "Optimize algorithms in hot code paths"
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

  defp analyze_diff("", _files, _hot_functions), do: []

  defp analyze_diff(diff, files, hot_functions) do
    added_lines =
      diff
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(String.trim_leading(&1), "+"))

    hot_calls =
      Enum.filter(hot_functions, fn func_name ->
        Enum.any?(added_lines, &String.contains?(&1, func_name))
      end)

    if length(hot_calls) > 0 do
      [
        %{
          type: :hot_path_modified,
          severity: :medium,
          file: hd(files ++ ["unknown"]),
          summary: "Modified code in potential hot path: #{Enum.join(hot_calls, ", ")}",
          recommendation: "Profile actual execution to confirm impact"
        }
      ]
    else
      []
    end
  end
end
