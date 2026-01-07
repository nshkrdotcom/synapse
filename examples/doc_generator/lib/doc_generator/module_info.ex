defmodule DocGenerator.ModuleInfo do
  @moduledoc """
  Represents extracted metadata about an Elixir module.

  Contains information about functions, types, callbacks, and existing documentation.
  """

  @enforce_keys [:module]
  defstruct [
    :module,
    :moduledoc,
    functions: [],
    types: [],
    callbacks: [],
    behaviours: [],
    existing_docs: nil,
    metadata: %{}
  ]

  @type function_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          type: :def | :defp | :defmacro,
          doc: String.t() | nil,
          signature: String.t() | nil,
          specs: [term()]
        }

  @type type_info :: %{
          name: atom(),
          type: term(),
          doc: String.t() | nil
        }

  @type callback_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          doc: String.t() | nil,
          spec: term()
        }

  @type t :: %__MODULE__{
          module: module(),
          moduledoc: String.t() | nil,
          functions: [function_info()],
          types: [type_info()],
          callbacks: [callback_info()],
          behaviours: [module()],
          existing_docs: term(),
          metadata: map()
        }

  @doc """
  Create a new ModuleInfo struct.
  """
  @spec new(module(), keyword()) :: t()
  def new(module, opts \\ []) when is_atom(module) do
    %__MODULE__{
      module: module,
      moduledoc: opts[:moduledoc],
      functions: opts[:functions] || [],
      types: opts[:types] || [],
      callbacks: opts[:callbacks] || [],
      behaviours: opts[:behaviours] || [],
      existing_docs: opts[:existing_docs],
      metadata: opts[:metadata] || %{}
    }
  end

  @doc """
  Convert ModuleInfo to a map suitable for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = info) do
    %{
      module: inspect(info.module),
      moduledoc: info.moduledoc,
      functions: info.functions,
      types: info.types,
      callbacks: info.callbacks,
      behaviours: Enum.map(info.behaviours, &inspect/1),
      metadata: info.metadata
    }
  end
end
