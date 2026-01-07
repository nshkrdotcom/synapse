defmodule ReviewBot.Providers.Codex do
  @moduledoc """
  Codex provider for code review.
  This is a mock implementation for demonstration.
  """
  @behaviour ReviewBot.Providers.Behaviour

  @impl true
  def available? do
    # In production, check for API key
    # System.get_env("OPENAI_API_KEY") != nil
    true
  end

  @impl true
  def review_code(code, _language) do
    # Simulate API call delay
    Process.sleep(Enum.random(700..1800))

    {:ok,
     %{
       provider: :codex,
       timestamp: DateTime.utc_now(),
       analysis: %{
         quality_score: Enum.random(65..90),
         issues: generate_codex_issues(code),
         suggestions: [
           "Consider edge cases in error handling",
           "Add input validation",
           "Improve code comments for maintainability"
         ],
         summary: "Codex analysis: Code shows #{assess_patterns(code)}"
       }
     }}
  end

  defp generate_codex_issues(code) do
    base_issues = [
      %{
        type: "error_handling",
        severity: "medium",
        line: Enum.random(1..20),
        message: "Missing error handling for edge cases"
      },
      %{
        type: "performance",
        severity: "low",
        line: Enum.random(1..20),
        message: "Consider optimizing this operation"
      }
    ]

    if String.contains?(code, "TODO") or String.contains?(code, "FIXME") do
      [
        %{
          type: "incomplete",
          severity: "high",
          message: "Code contains TODO/FIXME markers"
        }
        | base_issues
      ]
    else
      base_issues
    end
  end

  defp assess_patterns(_code) do
    patterns = [
      "good separation of concerns",
      "clear intent but needs refinement",
      "solid foundation with optimization opportunities"
    ]

    Enum.random(patterns)
  end
end
