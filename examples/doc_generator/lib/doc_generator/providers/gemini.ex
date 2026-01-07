defmodule DocGenerator.Providers.Gemini do
  @moduledoc """
  Gemini provider adapter for accessible documentation.

  Gemini excels at:
  - Clear explanations for broader audiences
  - Breaking down complex concepts
  - User-friendly documentation
  """

  @behaviour DocGenerator.Providers.Behaviour

  alias DocGenerator.ModuleInfo

  @impl true
  def name, do: :gemini

  @impl true
  def available? do
    System.get_env("GEMINI_API_KEY") != nil
  end

  @impl true
  def generate_module_doc(%ModuleInfo{} = module_info, opts \\ []) do
    style = Keyword.get(opts, :style, :casual)
    include_examples = Keyword.get(opts, :include_examples, true)

    prompt = build_prompt(module_info, style, include_examples)

    try do
      case Gemini.generate(prompt, model: "gemini-pro") do
        {:ok, response} ->
          case Gemini.extract_text(response) do
            {:ok, content} ->
              {:ok,
               %{
                 content: content,
                 provider: :gemini,
                 style: style,
                 metadata: %{model: "gemini-pro"}
               }}

            {:error, reason} ->
              {:error, {:gemini_error, reason}}
          end

        {:error, reason} ->
          {:error, {:gemini_error, reason}}
      end
    rescue
      e -> {:error, {:gemini_exception, Exception.message(e)}}
    end
  end

  defp build_prompt(module_info, style, include_examples) do
    """
    Generate #{style}-style documentation for this Elixir module.

    Module: #{inspect(module_info.module)}

    Purpose: Explain what this module does and why developers would use it.

    Available functionality:
    #{describe_functionality(module_info)}

    #{if include_examples, do: "Include simple, easy-to-understand examples.", else: ""}

    Write documentation that is:
    - Clear and accessible
    - Free of unnecessary jargon
    - Focused on practical understanding
    - Helpful for developers of all skill levels

    Return markdown documentation suitable for @moduledoc.
    """
  end

  defp describe_functionality(module_info) do
    parts = [
      "Functions: #{length(module_info.functions)}",
      if(module_info.types != [], do: "Custom types defined", else: nil),
      if(module_info.callbacks != [], do: "Behaviour with callbacks", else: nil)
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end
end
