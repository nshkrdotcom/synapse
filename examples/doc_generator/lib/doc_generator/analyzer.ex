defmodule DocGenerator.Analyzer do
  @moduledoc """
  Analyzes Elixir modules using introspection and Code module functions.

  Extracts function definitions, type specs, callbacks, and existing documentation.
  """

  alias DocGenerator.{Project, ModuleInfo}

  @doc """
  Analyze a module and extract its metadata.

  Uses `Code.fetch_docs/1` and module introspection to gather information
  about the module's structure and documentation.
  """
  @spec analyze_module(module()) :: {:ok, ModuleInfo.t()} | {:error, term()}
  def analyze_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      info =
        ModuleInfo.new(module,
          moduledoc: extract_moduledoc(module),
          functions: extract_functions(module),
          types: extract_types(module),
          callbacks: extract_callbacks(module),
          behaviours: extract_behaviours(module),
          existing_docs: fetch_existing_docs(module)
        )

      {:ok, info}
    else
      {:error, {:module_not_loaded, module}}
    end
  end

  @doc """
  List all modules in a project directory.

  Note: This requires the project to be compiled first.
  For this example, we return modules that are already loaded.
  """
  @spec list_modules(Project.t() | String.t()) :: [module()]
  def list_modules(%Project{modules: modules}) when modules != [] do
    modules
  end

  def list_modules(%Project{path: _path}) do
    # In a real implementation, this would compile the project
    # and discover modules. For this example, we return loaded modules.
    []
  end

  def list_modules(path) when is_binary(path) do
    project = Project.new(path)
    list_modules(project)
  end

  # Private functions for extraction

  defp extract_moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} -> moduledoc
      {:docs_v1, _, _, _, :hidden, _, _} -> :hidden
      {:docs_v1, _, _, _, :none, _, _} -> nil
      _ -> nil
    end
  end

  defp extract_functions(module) do
    if function_exported?(module, :__info__, 1) do
      module.__info__(:functions)
      |> Enum.map(fn {name, arity} ->
        %{
          name: name,
          arity: arity,
          type: :def,
          doc: extract_function_doc(module, name, arity),
          signature: format_signature(name, arity),
          specs: extract_specs(module, name, arity)
        }
      end)
      |> Enum.reject(&private_function?/1)
    else
      []
    end
  end

  defp extract_function_doc(module, name, arity) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.find_value(docs, fn
          {{:function, ^name, ^arity}, _anno, _signature, doc, _metadata} ->
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
  end

  defp extract_specs(module, name, arity) do
    if Code.ensure_loaded?(module) do
      case Code.Typespec.fetch_specs(module) do
        {:ok, specs} ->
          Enum.filter(specs, fn {{fun_name, fun_arity}, _spec} ->
            fun_name == name and fun_arity == arity
          end)

        _ ->
          []
      end
    else
      []
    end
  end

  defp extract_types(module) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.map(types, fn {kind, {name, _type, _args}} ->
          %{
            name: name,
            type: kind,
            doc: extract_type_doc(module, name)
          }
        end)

      _ ->
        []
    end
  end

  defp extract_type_doc(module, name) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.find_value(docs, fn
          {{:type, ^name, _arity}, _anno, _signature, doc, _metadata} ->
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
  end

  defp extract_callbacks(module) do
    case Code.Typespec.fetch_callbacks(module) do
      {:ok, callbacks} ->
        Enum.map(callbacks, fn {{name, arity}, _specs} ->
          %{
            name: name,
            arity: arity,
            doc: extract_callback_doc(module, name, arity),
            spec: nil
          }
        end)

      _ ->
        []
    end
  end

  defp extract_callback_doc(module, name, arity) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.find_value(docs, fn
          {{:callback, ^name, ^arity}, _anno, _signature, doc, _metadata} ->
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
  end

  defp extract_behaviours(module) do
    if function_exported?(module, :__info__, 1) do
      module.__info__(:attributes)
      |> Enum.filter(fn {key, _} -> key == :behaviour end)
      |> Enum.flat_map(fn {_, behaviours} -> behaviours end)
    else
      []
    end
  end

  defp fetch_existing_docs(module) do
    Code.fetch_docs(module)
  end

  defp format_signature(name, arity) do
    args = if arity == 0, do: "", else: Enum.map_join(1..arity, ", ", &"arg#{&1}")
    "#{name}(#{args})"
  end

  defp private_function?(%{name: name}) do
    String.starts_with?(Atom.to_string(name), "_")
  end
end
