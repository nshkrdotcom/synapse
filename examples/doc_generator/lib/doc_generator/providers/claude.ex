defmodule DocGenerator.Providers.Claude do
  @moduledoc """
  Claude provider adapter for technical documentation.

  Claude excels at:
  - Technical accuracy and precise terminology
  - Comprehensive explanations of complex concepts
  - Detailed API documentation with edge cases
  """

  @behaviour DocGenerator.Providers.Behaviour

  alias DocGenerator.ModuleInfo

  @impl true
  def name, do: :claude

  @impl true
  def available? do
    System.get_env("ANTHROPIC_API_KEY") != nil
  end

  @impl true
  def generate_module_doc(%ModuleInfo{} = module_info, opts \\ []) do
    style = Keyword.get(opts, :style, :formal)
    include_examples = Keyword.get(opts, :include_examples, true)

    prompt = build_prompt(module_info, style, include_examples)
    system_prompt = build_system_prompt(style)

    options = %ClaudeAgentSDK.Options{
      system_prompt: system_prompt,
      max_turns: 2
    }

    try do
      messages =
        ClaudeAgentSDK.query(prompt, options)
        |> Enum.to_list()

      case extract_content(messages) do
        {:ok, content} ->
          {:ok,
           %{
             content: content,
             provider: :claude,
             style: style,
             metadata: %{
               model: extract_model(messages),
               usage: extract_usage(messages)
             }
           }}

        {:error, reason} ->
          {:error, {:claude_error, reason}}
      end
    rescue
      e -> {:error, {:claude_exception, Exception.message(e)}}
    end
  end

  defp build_system_prompt(:formal) do
    """
    You are a technical documentation expert for Elixir code. Generate precise,
    comprehensive documentation following Elixir and ExDoc conventions. Use proper
    terminology, include type specifications, and explain edge cases.
    """
  end

  defp build_system_prompt(:casual) do
    """
    You are a friendly documentation writer for Elixir code. Generate clear,
    approachable documentation that explains concepts in plain language while
    remaining technically accurate.
    """
  end

  defp build_system_prompt(:tutorial) do
    """
    You are a tutorial writer for Elixir code. Generate documentation that
    teaches users how to use the code, with step-by-step examples and
    practical use cases.
    """
  end

  defp build_system_prompt(:reference) do
    """
    You are a reference documentation generator for Elixir code. Generate
    concise, structured documentation focused on API contracts, parameters,
    return values, and specifications.
    """
  end

  defp build_prompt(module_info, style, include_examples) do
    """
    Generate #{style} documentation for the following Elixir module.

    Module: #{inspect(module_info.module)}

    Functions:
    #{format_functions(module_info.functions)}

    Types:
    #{format_types(module_info.types)}

    Callbacks:
    #{format_callbacks(module_info.callbacks)}

    Behaviours: #{format_behaviours(module_info.behaviours)}

    #{if include_examples, do: "Include practical code examples where appropriate.", else: ""}

    Generate a comprehensive @moduledoc that:
    1. Explains the module's purpose and responsibilities
    2. Describes key functions and their use cases
    3. Provides usage examples (if requested)
    4. Notes any important behaviours or patterns

    Return only the markdown documentation content, without code fences or @moduledoc tags.
    """
  end

  defp format_functions([]), do: "None"

  defp format_functions(functions) do
    functions
    |> Enum.map(fn f ->
      doc = if f.doc, do: "\n  Doc: #{String.slice(f.doc, 0..100)}...", else: ""
      "- #{f.signature}#{doc}"
    end)
    |> Enum.join("\n")
  end

  defp format_types([]), do: "None"

  defp format_types(types) do
    types
    |> Enum.map(fn t -> "- @#{t.type} #{t.name}" end)
    |> Enum.join("\n")
  end

  defp format_callbacks([]), do: "None"

  defp format_callbacks(callbacks) do
    callbacks
    |> Enum.map(fn c -> "- #{c.name}/#{c.arity}" end)
    |> Enum.join("\n")
  end

  defp format_behaviours([]), do: "None"

  defp format_behaviours(behaviours) do
    Enum.map_join(behaviours, ", ", &inspect/1)
  end

  defp extract_content(messages) do
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
