defmodule ReviewBot.Providers.Gemini do
  @moduledoc """
  Gemini provider for code review.
  This is a mock implementation for demonstration.
  """
  @behaviour ReviewBot.Providers.Behaviour

  @impl true
  def available? do
    # In production, check for API key
    # System.get_env("GEMINI_API_KEY") != nil
    true
  end

  @impl true
  def review_code(code, language) do
    # Simulate API call delay
    Process.sleep(Enum.random(600..1600))

    {:ok,
     %{
       provider: :gemini,
       timestamp: DateTime.utc_now(),
       analysis: %{
         quality_score: Enum.random(75..92),
         issues: generate_gemini_issues(code, language),
         suggestions: [
           "Enhance code readability with better structure",
           "Add comprehensive test coverage",
           "Document complex logic paths"
         ],
         summary: "Gemini analysis: #{generate_summary(code)}"
       }
     }}
  end

  defp generate_gemini_issues(code, _language) do
    issues = [
      %{
        type: "readability",
        severity: "low",
        line: Enum.random(1..20),
        message: "Complex expression could be simplified"
      },
      %{
        type: "maintainability",
        severity: "medium",
        line: Enum.random(1..20),
        message: "Consider extracting this logic into a helper function"
      }
    ]

    lines = String.split(code, "\n")

    if length(lines) > 50 do
      [
        %{
          type: "organization",
          severity: "medium",
          message: "Large code block - consider breaking into smaller functions"
        }
        | issues
      ]
    else
      issues
    end
  end

  defp generate_summary(_code) do
    summaries = [
      "Generally well-written with minor improvements needed",
      "Solid implementation with good practices evident",
      "Functional code that would benefit from enhanced documentation"
    ]

    Enum.random(summaries)
  end
end
