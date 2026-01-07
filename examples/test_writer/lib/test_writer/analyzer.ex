defmodule TestWriter.Analyzer do
  @moduledoc """
  Analyzes Elixir modules to extract testable functions and metadata.

  Provides functionality to:
  - Extract public and private functions
  - Parse function documentation
  - Identify functions that need testing
  - Analyze code structure for test generation hints
  """

  alias TestWriter.Target

  @doc """
  Analyze a module and extract all testable functions.

  Returns a list of function info maps with name, arity, visibility, and documentation.
  """
  @spec analyze_module(Target.t()) :: {:ok, [Target.function_info()]} | {:error, term()}
  def analyze_module(%Target{module: module, source_code: source_code}) do
    cond do
      source_code ->
        analyze_source_code(source_code)

      Code.ensure_loaded?(module) ->
        analyze_loaded_module(module)

      true ->
        {:error, {:module_not_available, module}}
    end
  end

  @doc """
  Analyze loaded module using reflection.
  """
  @spec analyze_loaded_module(module()) :: {:ok, [Target.function_info()]}
  def analyze_loaded_module(module) when is_atom(module) do
    functions =
      module.__info__(:functions)
      |> Enum.reject(fn {name, _arity} -> name in [:__struct__, :__impl__] end)
      |> Enum.map(fn {name, arity} ->
        %{
          name: name,
          arity: arity,
          type: :public,
          doc: get_function_doc(module, name, arity),
          source: nil
        }
      end)

    {:ok, functions}
  rescue
    error -> {:error, {:analysis_failed, error}}
  end

  @doc """
  Analyze source code using Code.string_to_quoted/1.
  """
  @spec analyze_source_code(String.t()) :: {:ok, [Target.function_info()]} | {:error, term()}
  def analyze_source_code(source_code) when is_binary(source_code) do
    case Code.string_to_quoted(source_code) do
      {:ok, ast} ->
        functions = extract_functions_from_ast(ast, source_code)
        {:ok, functions}

      {:error, error} ->
        {:error, {:parse_error, error}}
    end
  end

  @doc """
  Filter functions to only those that should be tested.

  Excludes common functions like callbacks, generated functions, etc.
  """
  @spec filter_testable([Target.function_info()]) :: [Target.function_info()]
  def filter_testable(functions) when is_list(functions) do
    Enum.reject(functions, &skip_function?/1)
  end

  defp skip_function?(%{name: name, arity: arity}) do
    name_str = to_string(name)

    # Skip callbacks, internal functions, and common generated functions
    String.starts_with?(name_str, "__") or
      name in [:init, :handle_call, :handle_cast, :handle_info, :terminate, :code_change] or
      (name == :child_spec and arity == 1)
  end

  # Extract functions from AST
  defp extract_functions_from_ast(ast, source_code) do
    {_, functions} =
      Macro.prewalk(ast, [], fn
        {:def, _meta, [{name, _line_meta, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          doc = extract_doc_from_context(node)

          function_info = %{
            name: name,
            arity: arity,
            type: :public,
            doc: doc,
            source: extract_function_source(node, source_code)
          }

          {node, [function_info | acc]}

        {:defp, _meta, [{name, _line_meta, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0

          function_info = %{
            name: name,
            arity: arity,
            type: :private,
            doc: nil,
            source: extract_function_source(node, source_code)
          }

          {node, [function_info | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(functions)
  end

  defp extract_doc_from_context(_node) do
    # In a real implementation, we'd track @doc attributes
    # For now, return nil as we can't easily correlate docs without full parsing
    nil
  end

  defp extract_function_source(_node, _source_code) do
    # In a real implementation, we'd extract the actual function source
    # For now, return nil
    nil
  end

  defp get_function_doc(module, name, arity) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.find_value(docs, fn
          {{:function, ^name, ^arity}, _, _, doc, _} ->
            case doc do
              %{"en" => text} -> text
              _ -> nil
            end

          _ ->
            nil
        end)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Calculate coverage information for generated tests.
  """
  @spec calculate_coverage([Target.function_info()], [Target.function_info()]) ::
          Target.function_info()
  def calculate_coverage(all_functions, tested_functions) do
    total = length(all_functions)
    tested = length(tested_functions)

    %{
      functions_tested: tested,
      functions_total: total,
      percentage: if(total > 0, do: tested / total * 100, else: 0.0)
    }
  end
end
