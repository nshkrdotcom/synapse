defmodule DocGenerator.Outputs.Markdown do
  @moduledoc """
  Formats documentation output as Markdown.

  Produces clean, readable markdown suitable for README files,
  documentation sites, or inline module documentation.
  """

  alias DocGenerator.ModuleInfo

  @doc """
  Format module documentation as markdown.

  ## Options

    * `:include_header` - Include module name header (default: true)
    * `:include_toc` - Include table of contents (default: false)
    * `:header_level` - Starting header level (default: 1)
  """
  @spec format_module_doc(ModuleInfo.t(), String.t(), keyword()) :: String.t()
  def format_module_doc(%ModuleInfo{} = module_info, ai_content, opts \\ []) do
    include_header = Keyword.get(opts, :include_header, true)
    include_toc = Keyword.get(opts, :include_toc, false)
    header_level = Keyword.get(opts, :header_level, 1)

    parts = [
      if(include_header, do: format_header(module_info, header_level), else: nil),
      ai_content,
      if(include_toc, do: format_toc(module_info, header_level + 1), else: nil),
      format_functions_section(module_info.functions, header_level + 1),
      format_types_section(module_info.types, header_level + 1),
      format_callbacks_section(module_info.callbacks, header_level + 1)
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc """
  Format a project README with multiple modules.
  """
  @spec format_readme(map(), [map()], keyword()) :: String.t()
  def format_readme(project, module_docs, opts \\ []) do
    """
    # #{project[:name] || "Project Documentation"}

    #{if project[:version], do: "**Version:** #{project[:version]}\n", else: ""}
    ## Modules

    #{format_module_summaries(module_docs)}

    ## Installation

    Add to your `mix.exs`:

    ```elixir
    def deps do
      [
        {:#{snake_case(project[:name] || "project")}, "~> #{project[:version] || "0.1.0"}"}
      ]
    end
    ```

    #{if opts[:include_details], do: format_detailed_docs(module_docs), else: ""}
    """
  end

  defp format_header(module_info, level) do
    hashes = String.duplicate("#", level)
    "#{hashes} #{inspect(module_info.module)}"
  end

  defp format_toc(module_info, level) do
    hashes = String.duplicate("#", level)

    sections =
      [
        if(module_info.functions != [], do: "- [Functions](#functions)", else: nil),
        if(module_info.types != [], do: "- [Types](#types)", else: nil),
        if(module_info.callbacks != [], do: "- [Callbacks](#callbacks)", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    """
    #{hashes} Table of Contents

    #{sections}
    """
  end

  defp format_functions_section([], _level), do: nil

  defp format_functions_section(functions, level) do
    hashes = String.duplicate("#", level)

    function_list =
      functions
      |> Enum.map(fn f ->
        doc_preview = if f.doc, do: " - #{String.slice(f.doc, 0..80)}", else: ""
        "- `#{f.signature}`#{doc_preview}"
      end)
      |> Enum.join("\n")

    """
    #{hashes} Functions

    #{function_list}
    """
  end

  defp format_types_section([], _level), do: nil

  defp format_types_section(types, level) do
    hashes = String.duplicate("#", level)

    type_list =
      types
      |> Enum.map(fn t -> "- `@#{t.type} #{t.name}`" end)
      |> Enum.join("\n")

    """
    #{hashes} Types

    #{type_list}
    """
  end

  defp format_callbacks_section([], _level), do: nil

  defp format_callbacks_section(callbacks, level) do
    hashes = String.duplicate("#", level)

    callback_list =
      callbacks
      |> Enum.map(fn c -> "- `#{c.name}/#{c.arity}`" end)
      |> Enum.join("\n")

    """
    #{hashes} Callbacks

    #{callback_list}
    """
  end

  defp format_module_summaries([]), do: "No modules documented."

  defp format_module_summaries(module_docs) do
    module_docs
    |> Enum.map(fn doc ->
      module = doc[:module] || "Unknown"
      summary = if doc[:merged], do: String.slice(doc[:merged], 0..150), else: ""
      "### `#{inspect(module)}`\n\n#{summary}..."
    end)
    |> Enum.join("\n\n")
  end

  defp format_detailed_docs(module_docs) do
    """
    ## Detailed Documentation

    #{Enum.map_join(module_docs, "\n\n---\n\n", &format_module_detail/1)}
    """
  end

  defp format_module_detail(doc) do
    """
    ### #{inspect(doc[:module])}

    #{doc[:merged] || doc[:content] || "No documentation available."}
    """
  end

  defp snake_case(name) when is_binary(name) do
    name
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  defp snake_case(name), do: snake_case(to_string(name))
end
