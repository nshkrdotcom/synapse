defmodule DocGenerator.Outputs.ExDoc do
  @moduledoc """
  Formats documentation output for ExDoc compatibility.

  Generates documentation in a format that can be directly used as
  @moduledoc, @doc attributes in Elixir source files.
  """

  alias DocGenerator.ModuleInfo

  @doc """
  Format module documentation as an ExDoc-compatible @moduledoc string.

  Returns a properly formatted string that can be inserted into source code.
  """
  @spec format_moduledoc(ModuleInfo.t(), String.t()) :: String.t()
  def format_moduledoc(%ModuleInfo{} = module_info, ai_content) do
    """
    @moduledoc \"\"\"
    #{ai_content}

    ## Functions

    #{format_function_summaries(module_info.functions)}
    \"\"\"
    """
  end

  @doc """
  Generate @doc annotations for all functions in a module.
  """
  @spec format_function_docs(ModuleInfo.t(), map()) :: [{atom(), non_neg_integer(), String.t()}]
  def format_function_docs(%ModuleInfo{} = module_info, ai_docs) do
    module_info.functions
    |> Enum.map(fn f ->
      doc_content = Map.get(ai_docs, {f.name, f.arity}, generate_basic_doc(f))
      {f.name, f.arity, doc_content}
    end)
  end

  @doc """
  Format complete module documentation with @moduledoc and @doc attributes.

  Returns a string that represents how the module documentation should look.
  """
  @spec format_complete_module(ModuleInfo.t(), String.t(), map()) :: String.t()
  def format_complete_module(%ModuleInfo{} = module_info, moduledoc_content, function_docs) do
    """
    defmodule #{inspect(module_info.module)} do
      @moduledoc \"\"\"
      #{moduledoc_content}
      \"\"\"

    #{format_all_function_docs(module_info.functions, function_docs)}
    end
    """
  end

  defp format_function_summaries([]), do: "This module has no public functions."

  defp format_function_summaries(functions) do
    functions
    |> Enum.take(10)
    |> Enum.map(fn f ->
      existing_doc = if f.doc, do: String.slice(f.doc, 0..60), else: "No documentation"
      "- `#{f.signature}` - #{existing_doc}"
    end)
    |> Enum.join("\n")
  end

  defp format_all_function_docs(functions, ai_docs) do
    functions
    |> Enum.map(fn f ->
      doc = Map.get(ai_docs, {f.name, f.arity}, generate_basic_doc(f))

      """
        @doc \"\"\"
        #{doc}
        \"\"\"
        def #{f.signature} do
          # Implementation
        end
      """
    end)
    |> Enum.join("\n")
  end

  defp generate_basic_doc(function) do
    """
    #{function.signature}

    #{if function.doc, do: function.doc, else: "TODO: Add documentation"}
    """
  end
end
