defmodule CodingAgent.Prompts.Gemini do
  @moduledoc """
  Gemini-optimized prompts leveraging large context windows.

  Gemini responds well to:
  - Structured sections with clear headers
  - Large code context
  - Markdown formatting
  """

  alias CodingAgent.{Task, Prompts.Templates}

  @system_prompts %{
    generate: """
    Generate efficient, well-structured code.
    Focus on performance and clarity.
    Include brief comments explaining key decisions.
    """,
    review: """
    Review the code thoroughly. Consider:
    - Correctness and edge cases
    - Performance implications
    - Security considerations
    - Code style and readability

    Provide actionable feedback.
    """,
    analyze: """
    Analyze the provided code thoroughly. Consider:
    - Overall architecture and design patterns
    - Performance characteristics
    - Potential issues and risks
    - Suggestions for improvement

    Format your response in clear sections.
    """,
    explain: """
    Explain the code in detail. Cover:
    - What the code does at a high level
    - How each major component works
    - Any non-obvious logic or patterns

    Use examples where helpful.
    """,
    refactor: """
    Suggest refactoring improvements. For each suggestion:
    - Explain what to change
    - Why it improves the code
    - Show example before/after

    Prioritize high-impact changes.
    """,
    fix: """
    Diagnose and fix the issue. Include:
    - Root cause analysis
    - The fix with explanation
    - How to prevent similar issues
    """
  }

  @doc """
  Get the system prompt for a given task type.
  """
  @spec system_prompt_for(Task.task_type()) :: String.t()
  def system_prompt_for(type) do
    Map.get(@system_prompts, type, @system_prompts[:generate])
  end

  @doc """
  Format a task into a Gemini-optimized prompt.
  """
  @spec format_task(Task.t()) :: String.t()
  def format_task(%Task{} = task) do
    Templates.format_with_context(task)
  end
end
