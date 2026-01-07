defmodule CodingAgent.Prompts.Codex do
  @moduledoc """
  Codex-optimized prompts focused on action and tool usage.

  Codex responds well to:
  - Direct, actionable instructions
  - JSON output format
  - Tool-focused workflows
  """

  alias CodingAgent.Task

  @system_prompts %{
    generate: """
    Generate clean, idiomatic code. Follow existing codebase patterns.
    Include inline comments for complex logic. Output code only.
    """,
    review: """
    Review the code for bugs, security issues, and improvements.
    Be specific and actionable. List issues as bullet points.
    Rate severity: critical, warning, info.
    """,
    analyze: """
    Analyze the code structure and patterns.
    Identify key components, dependencies, and potential issues.
    Be concise and factual.
    """,
    explain: """
    Explain what the code does in clear, simple terms.
    Focus on the main logic and any non-obvious behavior.
    """,
    refactor: """
    Refactor the code to improve structure and readability.
    Show the before and after. Explain changes briefly.
    """,
    fix: """
    Fix the reported issue. Show the corrected code.
    Explain what was wrong and how you fixed it.
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
  Format a task into a Codex-optimized prompt.
  """
  @spec format_task(Task.t()) :: String.t()
  def format_task(%Task{} = task) do
    parts = [task.input]

    parts =
      if task.context do
        parts ++ ["Code:\n```\n#{task.context}\n```"]
      else
        parts
      end

    Enum.join(parts, "\n\n")
  end
end
