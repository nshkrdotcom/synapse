defmodule CodingAgent.Prompts.Templates do
  @moduledoc """
  Common prompt templates shared across providers.
  """

  alias CodingAgent.Task

  @doc """
  Format task with optional context section.
  """
  @spec format_with_context(Task.t()) :: String.t()
  def format_with_context(%Task{} = task) do
    sections = [format_task_section(task)]

    sections =
      if task.context do
        sections ++ [format_context_section(task)]
      else
        sections
      end

    sections =
      if task.files && task.files != [] do
        sections ++ [format_files_section(task)]
      else
        sections
      end

    Enum.join(sections, "\n\n")
  end

  defp format_task_section(task) do
    "## Task\n\n#{task.input}"
  end

  defp format_context_section(task) do
    lang = task.language || ""
    "## Code Context\n\n```#{lang}\n#{task.context}\n```"
  end

  defp format_files_section(task) do
    files = Enum.join(task.files, "\n- ")
    "## Relevant Files\n\n- #{files}"
  end

  @doc """
  Add output format instruction.
  """
  @spec with_format(String.t(), :json | :markdown | :plain) :: String.t()
  def with_format(prompt, :json) do
    prompt <> "\n\nRespond with valid JSON only."
  end

  def with_format(prompt, :markdown) do
    prompt <> "\n\nFormat your response in Markdown."
  end

  def with_format(prompt, :plain) do
    prompt
  end
end
