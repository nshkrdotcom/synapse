defmodule DataPipeline.Lineage do
  @moduledoc """
  Tracks data provenance through the pipeline.

  Lineage captures where data came from, what transformations were applied,
  and when each step occurred. This enables full auditability and debugging.

  ## Example

      lineage = Lineage.new(:api, %{endpoint: "/events"})

      lineage
      |> Lineage.add_transformation(:extract, %{batch_id: 1})
      |> Lineage.add_transformation(:classify, %{classifier: :sentiment})
      |> Lineage.add_transformation(:transform, %{transformer: :enrich})
      |> Lineage.add_transformation(:load, %{destination: :s3})
  """

  @type transformation :: %{
          step: atom(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @type t :: %__MODULE__{
          record_id: String.t(),
          source: atom() | String.t(),
          source_metadata: map(),
          transformations: [transformation()],
          created_at: DateTime.t()
        }

  defstruct [:record_id, :source, :source_metadata, :transformations, :created_at]

  @doc """
  Creates a new lineage record for a data item.

  ## Examples

      Lineage.new(:database, %{table: "events", query_id: "123"})
      Lineage.new(:api, %{endpoint: "/data", timestamp: ~U[2024-01-15 10:00:00Z]})
  """
  @spec new(atom() | String.t(), map()) :: t()
  def new(source, source_metadata \\ %{}) do
    %__MODULE__{
      record_id: generate_id(),
      source: source,
      source_metadata: source_metadata,
      transformations: [],
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Adds a transformation step to the lineage.

  ## Examples

      lineage
      |> Lineage.add_transformation(:classify, %{result: :high_priority})
      |> Lineage.add_transformation(:transform, %{transformer: :enrich})
  """
  @spec add_transformation(t(), atom(), map()) :: t()
  def add_transformation(%__MODULE__{} = lineage, step, metadata \\ %{})
      when is_atom(step) do
    transformation = %{
      step: step,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }

    %{lineage | transformations: lineage.transformations ++ [transformation]}
  end

  @doc """
  Returns all transformation steps in order.
  """
  @spec get_transformations(t()) :: [transformation()]
  def get_transformations(%__MODULE__{} = lineage) do
    lineage.transformations
  end

  @doc """
  Returns the pipeline path as a list of step names.

  ## Examples

      Lineage.pipeline_path(lineage)
      # => [:extract, :classify, :transform, :load]
  """
  @spec pipeline_path(t()) :: [atom()]
  def pipeline_path(%__MODULE__{} = lineage) do
    Enum.map(lineage.transformations, & &1.step)
  end

  @doc """
  Finds a specific transformation by step name.
  """
  @spec find_transformation(t(), atom()) :: transformation() | nil
  def find_transformation(%__MODULE__{} = lineage, step) when is_atom(step) do
    Enum.find(lineage.transformations, &(&1.step == step))
  end

  @doc """
  Calculates the total processing time from creation to last transformation.
  """
  @spec total_duration(t()) :: integer()
  def total_duration(%__MODULE__{transformations: []} = lineage) do
    DateTime.diff(DateTime.utc_now(), lineage.created_at, :millisecond)
  end

  def total_duration(%__MODULE__{transformations: transformations} = lineage) do
    last_timestamp = List.last(transformations).timestamp
    DateTime.diff(last_timestamp, lineage.created_at, :millisecond)
  end

  @doc """
  Converts lineage to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = lineage) do
    %{
      record_id: lineage.record_id,
      source: lineage.source,
      source_metadata: lineage.source_metadata,
      transformations: lineage.transformations,
      created_at: DateTime.to_iso8601(lineage.created_at)
    }
  end

  @doc """
  Reconstructs lineage from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    created_at =
      case map.created_at || map["created_at"] do
        nil -> DateTime.utc_now()
        str when is_binary(str) -> DateTime.from_iso8601(str) |> elem(1)
        %DateTime{} = dt -> dt
      end

    %__MODULE__{
      record_id: map.record_id || map["record_id"],
      source: map.source || map["source"],
      source_metadata: map.source_metadata || map["source_metadata"] || %{},
      transformations: map.transformations || map["transformations"] || [],
      created_at: created_at
    }
  end

  # Generates a unique lineage ID
  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
