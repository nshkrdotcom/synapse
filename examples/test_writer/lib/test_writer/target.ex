defmodule TestWriter.Target do
  @moduledoc """
  Represents a target module to generate tests for.

  Contains the module name, functions to test, and file path information.
  """

  @enforce_keys [:id, :module, :path]
  defstruct [
    :id,
    :module,
    :path,
    :functions,
    :source_code,
    :metadata,
    :inserted_at
  ]

  @type function_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          type: :public | :private,
          doc: String.t() | nil,
          source: String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          module: module(),
          path: String.t(),
          functions: [function_info()] | nil,
          source_code: String.t() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  @doc """
  Create a new target from a module name and optional file path.

  ## Options

    * `:path` - File path to the module source (required if module not loaded)
    * `:functions` - List of specific functions to target
    * `:metadata` - Additional metadata map
  """
  @spec new(module(), keyword()) :: t()
  def new(module, opts \\ []) when is_atom(module) do
    %__MODULE__{
      id: generate_id(module),
      module: module,
      path: opts[:path] || infer_path(module),
      functions: opts[:functions],
      source_code: opts[:source_code],
      metadata: opts[:metadata] || %{},
      inserted_at: DateTime.utc_now()
    }
  end

  @doc """
  Generate a unique target ID based on module name.
  """
  @spec generate_id(module()) :: String.t()
  def generate_id(module) when is_atom(module) do
    "target_#{module |> Module.split() |> Enum.join("_") |> String.downcase()}"
  end

  @doc """
  Attempt to infer the file path for a module.
  """
  @spec infer_path(module()) :: String.t() | nil
  def infer_path(module) when is_atom(module) do
    case :code.which(module) do
      path when is_list(path) ->
        path
        |> to_string()
        |> String.replace(~r/\.beam$/, ".ex")

      _ ->
        # Convert module name to likely file path
        module
        |> Module.split()
        |> Enum.map(&Macro.underscore/1)
        |> Path.join()
        |> Kernel.<>(".ex")
    end
  end

  @doc """
  Convert target to a map suitable for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = target) do
    %{
      id: target.id,
      module: target.module,
      path: target.path,
      functions: target.functions,
      source_code: target.source_code,
      metadata: target.metadata,
      inserted_at: target.inserted_at && DateTime.to_iso8601(target.inserted_at)
    }
  end

  @doc """
  Build a target from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map[:id] || map["id"],
      module: map[:module] || map["module"],
      path: map[:path] || map["path"],
      functions: map[:functions] || map["functions"],
      source_code: map[:source_code] || map["source_code"],
      metadata: map[:metadata] || map["metadata"] || %{},
      inserted_at: parse_datetime(map[:inserted_at] || map["inserted_at"])
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%DateTime{} = dt), do: dt
end
