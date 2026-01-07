defmodule CodingAgent.Providers.Codex do
  @moduledoc """
  Codex provider adapter using codex_sdk.

  Codex excels at:
  - Quick code reviews with file context
  - Bug fixes with tool-calling capabilities
  - Tasks requiring direct file manipulation
  """

  @behaviour CodingAgent.Providers.Behaviour

  alias CodingAgent.{Task, Prompts}

  @impl true
  def name, do: :codex

  @impl true
  def available? do
    System.get_env("OPENAI_API_KEY") != nil
  end

  @impl true
  def execute(%Task{} = task, opts \\ []) do
    system_prompt = Prompts.Codex.system_prompt_for(task.type)
    prompt = Prompts.Codex.format_task(task)

    codex_opts = build_codex_opts(system_prompt, opts)
    thread_opts = build_thread_opts(task)

    try do
      with {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
           {:ok, result} <- Codex.Thread.run(thread, prompt) do
        {:ok,
         %{
           content: extract_response_text(result),
           provider: :codex,
           model: codex_opts[:model] || "o4-mini",
           usage: result.usage,
           raw: result
         }}
      else
        {:error, reason} -> {:error, {:codex_error, reason}}
      end
    rescue
      e -> {:error, {:codex_exception, Exception.message(e)}}
    end
  end

  defp build_codex_opts(system_prompt, opts) do
    %{
      model: Keyword.get(opts, :model, "o4-mini"),
      instructions: system_prompt
    }
  end

  defp build_thread_opts(task) do
    %{
      metadata: %{
        task_id: task.id,
        type: task.type
      }
    }
  end

  defp extract_response_text(%{final_response: %{text: text}}) when is_binary(text), do: text

  defp extract_response_text(%{final_response: response}) when is_map(response),
    do: Map.get(response, :text, "")

  defp extract_response_text(_), do: ""
end
