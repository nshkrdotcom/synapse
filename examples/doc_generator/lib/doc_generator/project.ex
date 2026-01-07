defmodule DocGenerator.Project do
  @moduledoc """
  Represents an Elixir project to be documented.

  Contains the project path, discovered modules, and documentation configuration.
  """

  @enforce_keys [:path]
  defstruct [
    :path,
    :name,
    :version,
    modules: [],
    config: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          name: String.t() | nil,
          version: String.t() | nil,
          modules: [module()],
          config: map(),
          metadata: map()
        }

  @doc """
  Create a new project from a path.

  ## Options

    * `:name` - Project name (inferred from mix.exs if not provided)
    * `:version` - Project version (inferred from mix.exs if not provided)
    * `:config` - Documentation configuration map
    * `:metadata` - Additional metadata
  """
  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) when is_binary(path) do
    %__MODULE__{
      path: Path.expand(path),
      name: opts[:name],
      version: opts[:version],
      modules: opts[:modules] || [],
      config: opts[:config] || %{},
      metadata: opts[:metadata] || %{}
    }
  end

  @doc """
  Load project information from a directory.

  Attempts to read mix.exs and discover project details.
  """
  @spec from_directory(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_directory(path, opts \\ []) do
    expanded_path = Path.expand(path)

    if File.dir?(expanded_path) do
      project = new(expanded_path, opts)
      {:ok, project}
    else
      {:error, {:invalid_directory, path}}
    end
  end

  @doc """
  Convert project to a map suitable for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = project) do
    %{
      path: project.path,
      name: project.name,
      version: project.version,
      modules: Enum.map(project.modules, &inspect/1),
      config: project.config,
      metadata: project.metadata
    }
  end
end
