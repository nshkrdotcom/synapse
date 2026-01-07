defmodule CodingAgent.Providers.Claude do
  @moduledoc """
  Claude provider adapter using claude_agent_sdk.

  Claude excels at:
  - Complex code generation with careful reasoning
  - Refactoring with step-by-step explanations
  - Tasks requiring deep understanding
  """

  @behaviour CodingAgent.Providers.Behaviour

  alias CodingAgent.{Task, Prompts}

  @impl true
  def name, do: :claude

  @impl true
  def available? do
    # Check if API key is set or claude CLI is authenticated
    System.get_env("ANTHROPIC_API_KEY") != nil
  end

  @impl true
  def execute(%Task{} = task, opts \\ []) do
    system_prompt = Prompts.Claude.system_prompt_for(task.type)
    prompt = Prompts.Claude.format_task(task)

    options = build_options(system_prompt, opts)

    try do
      messages =
        ClaudeAgentSDK.query(prompt, options)
        |> Enum.to_list()

      case extract_result(messages) do
        {:ok, content} ->
          {:ok,
           %{
             content: content,
             provider: :claude,
             model: extract_model(messages),
             usage: extract_usage(messages),
             raw: messages
           }}

        {:error, reason} ->
          {:error, {:claude_error, reason}}
      end
    rescue
      e -> {:error, {:claude_exception, Exception.message(e)}}
    end
  end

  defp build_options(system_prompt, opts) do
    %ClaudeAgentSDK.Options{
      system_prompt: system_prompt,
      max_turns: Keyword.get(opts, :max_turns, 3)
    }
  end

  defp extract_result(messages) do
    text =
      messages
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ClaudeAgentSDK.ContentExtractor.extract_text/1)
      |> Enum.join("\n")

    if text == "", do: {:error, :no_response}, else: {:ok, text}
  end

  defp extract_model(messages) do
    Enum.find_value(messages, fn msg ->
      case msg do
        %{model: model} when is_binary(model) -> model
        _ -> nil
      end
    end)
  end

  defp extract_usage(messages) do
    Enum.find_value(messages, fn msg ->
      case msg do
        %{usage: usage} when is_map(usage) -> usage
        _ -> nil
      end
    end) || %{}
  end
end
