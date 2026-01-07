defmodule CodingAgent.Providers.Gemini do
  @moduledoc """
  Gemini provider adapter using gemini_ex.

  Gemini excels at:
  - Code analysis with large context windows
  - Clear explanations and documentation
  - Fast responses for simple queries
  """

  @behaviour CodingAgent.Providers.Behaviour

  alias CodingAgent.{Task, Prompts}

  @impl true
  def name, do: :gemini

  @impl true
  def available? do
    System.get_env("GEMINI_API_KEY") != nil
  end

  @impl true
  def execute(%Task{} = task, opts \\ []) do
    system_prompt = Prompts.Gemini.system_prompt_for(task.type)
    prompt = Prompts.Gemini.format_task(task)

    gemini_opts = build_gemini_opts(system_prompt, opts)

    try do
      case Gemini.text(prompt, gemini_opts) do
        {:ok, text} ->
          {:ok,
           %{
             content: text,
             provider: :gemini,
             model: gemini_opts[:model],
             usage: nil,
             raw: text
           }}

        {:error, %Gemini.Error{} = error} ->
          {:error, {:gemini_error, error.message}}

        {:error, reason} ->
          {:error, {:gemini_error, reason}}
      end
    rescue
      e -> {:error, {:gemini_exception, Exception.message(e)}}
    end
  end

  defp build_gemini_opts(system_prompt, opts) do
    [
      model: Keyword.get(opts, :model, "gemini-2.0-flash-exp"),
      system_instruction: system_prompt,
      temperature: Keyword.get(opts, :temperature, 0.3),
      max_output_tokens: Keyword.get(opts, :max_tokens, 8192)
    ]
  end
end
