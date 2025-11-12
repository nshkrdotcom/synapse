defmodule Synapse.Actions.Security.CheckXSS do
  @moduledoc """
  Detects potential XSS (Cross-Site Scripting) vulnerabilities in code diffs.

  Analyzes diffs for patterns indicating XSS risks:
  - Use of `raw/1` function in templates
  - Unescaped user input rendering
  - Dangerous HTML attributes
  - innerHTML assignments

  Returns findings with severity ratings and remediation recommendations.
  """

  use Jido.Action,
    name: "check_xss",
    description: "Analyzes diffs for XSS vulnerabilities",
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

    recommended_actions =
      if length(findings) > 0 do
        [
          "Remove 'raw/1' calls and use proper HTML escaping",
          "Sanitize user-generated content before rendering",
          "Review security implications of rendering unescaped content"
        ]
      else
        []
      end

    result = %{
      findings: findings,
      confidence: confidence,
      recommended_actions: recommended_actions
    }

    Logger.debug("XSS check completed",
      findings_count: length(findings),
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
      detect_xss_in_line(line, idx, files)
    end)
    |> Enum.uniq_by(&{&1.type, &1.file})
  end

  defp detect_xss_in_line(line, _idx, files) do
    patterns = xss_patterns()

    has_xss? =
      Enum.any?(patterns, fn pattern ->
        Regex.match?(pattern, line)
      end)

    if has_xss? do
      file = determine_file(files)

      severity =
        cond do
          Regex.match?(~r/raw\(.*@user/i, line) -> :high
          Regex.match?(~r/raw\(/i, line) -> :medium
          true -> :medium
        end

      [
        %{
          type: :xss,
          severity: severity,
          file: file,
          summary: "Potential XSS vulnerability: Unescaped content rendering detected",
          recommendation: "Remove 'raw/1' calls and use proper HTML escaping"
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
  defp calculate_confidence(_diff, _findings), do: 0.8

  defp xss_patterns do
    [
      # Template raw/1 usage
      ~r/raw\(/i,
      # HTML unsafe rendering patterns
      ~r/innerHTML\s*=/i,
      ~r/dangerouslySetInnerHTML/i,
      # Other unsafe patterns
      ~r/v-html\s*=/i
    ]
  end
end
