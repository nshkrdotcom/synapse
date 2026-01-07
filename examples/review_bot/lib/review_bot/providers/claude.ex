defmodule ReviewBot.Providers.Claude do
  @moduledoc """
  Claude AI provider for code review.
  This is a mock implementation for demonstration.
  """
  @behaviour ReviewBot.Providers.Behaviour

  @impl true
  def available? do
    # In production, check for API key
    # System.get_env("ANTHROPIC_API_KEY") != nil
    true
  end

  @impl true
  def review_code(code, language) do
    # Simulate API call delay
    Process.sleep(Enum.random(500..1500))

    {:ok,
     %{
       provider: :claude,
       timestamp: DateTime.utc_now(),
       analysis: %{
         quality_score: Enum.random(70..95),
         issues: generate_mock_issues(code, language, :claude),
         suggestions: generate_mock_suggestions(:claude),
         summary: "Claude AI analysis: #{describe_code_quality(code)}"
       }
     }}
  end

  defp generate_mock_issues(code, language, _provider) do
    issues = [
      %{
        type: "complexity",
        severity: "medium",
        line: Enum.random(1..20),
        message: "Function complexity could be reduced"
      },
      %{
        type: "naming",
        severity: "low",
        line: Enum.random(1..20),
        message: "Consider more descriptive variable names"
      }
    ]

    if String.length(code) > 500 do
      [
        %{
          type: "length",
          severity: "medium",
          message: "Function is quite long, consider breaking it down"
        }
        | issues
      ]
    else
      issues
    end
    |> maybe_add_language_specific_issue(language)
  end

  defp maybe_add_language_specific_issue(issues, "elixir") do
    [
      %{
        type: "pattern",
        severity: "low",
        message: "Consider using pattern matching for clarity"
      }
      | issues
    ]
  end

  defp maybe_add_language_specific_issue(issues, _), do: issues

  defp generate_mock_suggestions(:claude) do
    [
      "Add documentation for public functions",
      "Consider adding type specifications",
      "Extract magic numbers into named constants"
    ]
  end

  defp describe_code_quality(code) do
    cond do
      String.length(code) < 100 -> "concise and focused implementation"
      String.length(code) < 500 -> "well-structured code with room for improvement"
      true -> "comprehensive implementation that may benefit from refactoring"
    end
  end
end
