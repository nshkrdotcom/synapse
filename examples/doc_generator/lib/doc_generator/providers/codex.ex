defmodule DocGenerator.Providers.Codex do
  @moduledoc """
  Codex provider adapter for code-focused documentation.

  Codex excels at:
  - Generating practical code examples
  - Demonstrating usage patterns
  - Showing common use cases and idioms
  """

  @behaviour DocGenerator.Providers.Behaviour

  alias DocGenerator.ModuleInfo

  @impl true
  def name, do: :codex

  @impl true
  def available? do
    System.get_env("OPENAI_API_KEY") != nil
  end

  @impl true
  def generate_module_doc(%ModuleInfo{} = module_info, opts \\ []) do
    style = Keyword.get(opts, :style, :tutorial)
    include_examples = Keyword.get(opts, :include_examples, true)

    prompt = build_prompt(module_info, style, include_examples)
    system_prompt = build_system_prompt(style)

    codex_opts = %{
      model: "o4-mini",
      instructions: system_prompt
    }

    thread_opts = %{
      metadata: %{
        module: inspect(module_info.module),
        style: style
      }
    }

    try do
      with {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
           {:ok, result} <- Codex.Thread.run(thread, prompt) do
        {:ok,
         %{
           content: extract_response_text(result),
           provider: :codex,
           style: style,
           metadata: %{model: "o4-mini"}
         }}
      else
        {:error, reason} -> {:error, {:codex_error, reason}}
      end
    rescue
      e -> {:error, {:codex_exception, Exception.message(e)}}
    end
  end

  defp extract_response_text(%{final_response: %{text: text}}) when is_binary(text), do: text

  defp extract_response_text(%{final_response: response}) when is_map(response),
    do: Map.get(response, :text, "")

  defp extract_response_text(_), do: ""

  defp build_system_prompt(:tutorial) do
    """
    You are an expert at writing code examples and tutorials for Elixir.
    Generate documentation rich with practical examples showing how to use the code.
    """
  end

  defp build_system_prompt(style) do
    """
    You are a documentation generator for Elixir code with a focus on #{style} style.
    Include clear code examples demonstrating the API usage.
    """
  end

  defp build_prompt(module_info, _style, include_examples) do
    """
    Generate documentation for the Elixir module: #{inspect(module_info.module)}

    This module has:
    - #{length(module_info.functions)} public functions
    - #{length(module_info.types)} custom types
    - #{length(module_info.callbacks)} callbacks

    Key functions:
    #{format_key_functions(module_info.functions)}

    #{if include_examples, do: "Focus on providing comprehensive code examples for the main functions.", else: ""}

    Generate markdown documentation that developers can immediately understand and use.
    """
  end

  defp format_key_functions(functions) do
    functions
    |> Enum.take(5)
    |> Enum.map(fn f -> "- #{f.signature}" end)
    |> Enum.join("\n")
  end
end
