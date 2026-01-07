defmodule DataPipeline.Record do
  @moduledoc """
  Represents a data record flowing through the pipeline with lineage tracking.

  Each record carries its data content along with lineage information that
  tracks its provenance through the pipeline.
  """

  alias DataPipeline.Lineage

  @type t :: %__MODULE__{
          id: String.t(),
          content: map(),
          lineage: Lineage.t(),
          metadata: map()
        }

  defstruct [:id, :content, :lineage, :metadata]

  @doc """
  Creates a new record from raw data.

  ## Examples

      Record.new(%{text: "Hello, world!"}, source: :api)
      Record.new(%{value: 42}, source: :database, partition: "2024-01-15")
  """
  @spec new(map(), keyword()) :: t()
  def new(content, opts \\ []) when is_map(content) do
    source = Keyword.get(opts, :source, :unknown)
    metadata = Keyword.get(opts, :metadata, %{})

    %__MODULE__{
      id: generate_id(),
      content: content,
      lineage: Lineage.new(source, metadata),
      metadata: metadata
    }
  end

  @doc """
  Creates a batch of records from a list of data items.
  """
  @spec new_batch([map()], keyword()) :: [t()]
  def new_batch(items, opts \\ []) when is_list(items) do
    Enum.map(items, &new(&1, opts))
  end

  @doc """
  Adds a transformation step to the record's lineage.
  """
  @spec transform(t(), atom(), map()) :: t()
  def transform(%__MODULE__{} = record, step, metadata \\ %{}) do
    %{record | lineage: Lineage.add_transformation(record.lineage, step, metadata)}
  end

  @doc """
  Updates the record's content while preserving lineage.
  """
  @spec update_content(t(), map()) :: t()
  def update_content(%__MODULE__{} = record, new_content) when is_map(new_content) do
    %{record | content: new_content}
  end

  @doc """
  Merges additional data into the record's content.
  """
  @spec merge_content(t(), map()) :: t()
  def merge_content(%__MODULE__{} = record, additional_data) when is_map(additional_data) do
    %{record | content: Map.merge(record.content, additional_data)}
  end

  @doc """
  Adds metadata to the record.
  """
  @spec add_metadata(t(), map()) :: t()
  def add_metadata(%__MODULE__{} = record, metadata) when is_map(metadata) do
    %{record | metadata: Map.merge(record.metadata, metadata)}
  end

  @doc """
  Converts the record to a plain map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = record) do
    %{
      id: record.id,
      content: record.content,
      lineage: Lineage.to_map(record.lineage),
      metadata: record.metadata
    }
  end

  @doc """
  Reconstructs a record from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map.id || map["id"],
      content: map.content || map["content"],
      lineage: Lineage.from_map(map.lineage || map["lineage"]),
      metadata: map.metadata || map["metadata"] || %{}
    }
  end

  # Generates a unique record ID
  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
