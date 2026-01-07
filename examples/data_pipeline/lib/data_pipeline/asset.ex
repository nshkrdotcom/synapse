defmodule DataPipeline.Asset do
  @moduledoc """
  Defines a data asset with dependencies and materialization logic.

  Inspired by Dagster and FlowStone's asset-first approach, an Asset represents
  a data artifact that can be materialized (computed) based on its dependencies.

  ## Example

      Asset.new(:raw_events,
        description: "Raw events from source systems",
        materializer: fn _deps ->
          {:ok, fetch_events()}
        end
      )

      Asset.new(:cleaned_events,
        description: "Validated and cleaned events",
        deps: [:raw_events],
        materializer: fn %{raw_events: events} ->
          {:ok, clean_and_validate(events)}
        end
      )
  """

  @type materializer_fn :: (map() -> {:ok, term()} | {:error, term()})

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t() | nil,
          deps: [atom()],
          materializer: materializer_fn(),
          metadata: map()
        }

  defstruct [:name, :description, :deps, :materializer, :metadata]

  @doc """
  Creates a new asset definition.

  ## Options

    * `:description` - Human-readable description
    * `:deps` - List of asset names this asset depends on
    * `:materializer` - Function that computes this asset's value
    * `:metadata` - Additional metadata map

  ## Examples

      Asset.new(:my_asset,
        description: "My data asset",
        deps: [:upstream_asset],
        materializer: fn %{upstream_asset: data} ->
          {:ok, transform(data)}
        end
      )
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    unless Keyword.has_key?(opts, :materializer) do
      raise ArgumentError, "asset #{inspect(name)} requires a :materializer function"
    end

    materializer = Keyword.fetch!(opts, :materializer)

    unless is_function(materializer, 1) do
      raise ArgumentError, "asset materializer must be a function of arity 1"
    end

    %__MODULE__{
      name: name,
      description: Keyword.get(opts, :description),
      deps: Keyword.get(opts, :deps, []),
      materializer: materializer,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Materializes (computes) an asset given its dependencies.
  """
  @spec materialize(t(), map()) :: {:ok, term()} | {:error, term()}
  def materialize(%__MODULE__{} = asset, dependencies \\ %{}) do
    asset.materializer.(dependencies)
  end

  @doc """
  Validates asset dependencies are well-formed.
  """
  @spec validate_dependencies([t()]) :: :ok | {:error, term()}
  def validate_dependencies(assets) when is_list(assets) do
    asset_names = MapSet.new(assets, & &1.name)

    Enum.reduce_while(assets, :ok, fn asset, _acc ->
      case validate_asset_deps(asset, asset_names) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_asset_deps(%{name: name, deps: deps}, asset_names) do
    missing_deps =
      deps
      |> Enum.reject(&MapSet.member?(asset_names, &1))

    case missing_deps do
      [] ->
        :ok

      missing ->
        {:error, "asset #{inspect(name)} depends on unknown assets: #{inspect(missing)}"}
    end
  end

  @doc """
  Sorts assets in topological order for execution.
  """
  @spec topological_sort([t()]) :: {:ok, [t()]} | {:error, term()}
  def topological_sort(assets) when is_list(assets) do
    with :ok <- validate_dependencies(assets),
         {:ok, sorted} <- do_topological_sort(assets) do
      {:ok, sorted}
    end
  end

  defp do_topological_sort(assets) do
    # Kahn's algorithm for topological sort
    # Build adjacency list: node -> [nodes that depend on it]
    asset_map = Map.new(assets, &{&1.name, &1})

    # Build reverse graph: for each node, who depends on it?
    adjacency = build_adjacency_list(assets)

    # Calculate in-degrees: how many dependencies does each node have?
    in_degree =
      Map.new(assets, fn asset ->
        {asset.name, length(asset.deps)}
      end)

    # Find all nodes with in-degree 0 (no dependencies)
    queue =
      assets
      |> Enum.filter(fn asset -> length(asset.deps) == 0 end)
      |> Enum.map(& &1.name)

    kahn_sort(queue, adjacency, in_degree, asset_map, [])
  end

  defp build_adjacency_list(assets) do
    # For each asset, track which other assets depend on it
    Enum.reduce(assets, %{}, fn asset, acc ->
      Enum.reduce(asset.deps, acc, fn dep, inner_acc ->
        Map.update(inner_acc, dep, [asset.name], fn existing ->
          [asset.name | existing]
        end)
      end)
    end)
  end

  defp kahn_sort([], _adjacency, in_degree, _asset_map, result) do
    # Check if all nodes were processed
    remaining = Enum.filter(in_degree, fn {_node, degree} -> degree > 0 end)

    if length(remaining) > 0 do
      {:error, "cyclic dependency detected in assets"}
    else
      {:ok, Enum.reverse(result)}
    end
  end

  defp kahn_sort([node | rest], adjacency, in_degree, asset_map, result) do
    # Add this node to result
    asset = Map.fetch!(asset_map, node)
    new_result = [asset | result]

    # Get all nodes that depend on this node
    dependents = Map.get(adjacency, node, [])

    # Decrease in-degree for all dependents
    new_in_degree =
      Enum.reduce(dependents, in_degree, fn dependent, acc ->
        Map.update!(acc, dependent, &(&1 - 1))
      end)

    # Add newly freed nodes (in-degree became 0) to queue
    newly_freed =
      dependents
      |> Enum.filter(fn dep -> new_in_degree[dep] == 0 end)

    new_queue = rest ++ newly_freed

    kahn_sort(new_queue, adjacency, new_in_degree, asset_map, new_result)
  end
end
