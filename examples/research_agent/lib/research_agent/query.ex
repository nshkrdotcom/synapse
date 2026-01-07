defmodule ResearchAgent.Query do
  @moduledoc """
  Represents a research query with topic, depth, and configuration.

  Queries encapsulate the research parameters and are used throughout
  the workflow to track the research request and its metadata.
  """

  @enforce_keys [:id, :topic]
  defstruct [
    :id,
    :topic,
    :depth,
    :max_sources,
    :reliability_threshold,
    :include_citations,
    :metadata,
    :inserted_at
  ]

  @type depth :: :quick | :deep | :comprehensive
  @type t :: %__MODULE__{
          id: String.t(),
          topic: String.t(),
          depth: depth(),
          max_sources: pos_integer(),
          reliability_threshold: float(),
          include_citations: boolean(),
          metadata: map(),
          inserted_at: DateTime.t()
        }

  @doc """
  Create a new research query.

  ## Options

    * `:depth` - Research depth (default: `:quick`)
    * `:max_sources` - Maximum sources to gather (default: 10)
    * `:reliability_threshold` - Minimum source reliability (default: 0.6)
    * `:include_citations` - Include citations in output (default: true)
    * `:metadata` - Additional metadata map

  ## Examples

      Query.new("Quantum computing")
      Query.new("AI ethics", depth: :deep, max_sources: 20)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(topic, opts \\ []) when is_binary(topic) do
    %__MODULE__{
      id: generate_id(),
      topic: topic,
      depth: Keyword.get(opts, :depth, :quick),
      max_sources: Keyword.get(opts, :max_sources, 10),
      reliability_threshold: Keyword.get(opts, :reliability_threshold, 0.6),
      include_citations: Keyword.get(opts, :include_citations, true),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: DateTime.utc_now()
    }
  end

  @doc """
  Generate a unique query ID.
  """
  @spec generate_id() :: String.t()
  def generate_id do
    "query_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  @doc """
  Convert query to a map suitable for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = query) do
    %{
      id: query.id,
      topic: query.topic,
      depth: query.depth,
      max_sources: query.max_sources,
      reliability_threshold: query.reliability_threshold,
      include_citations: query.include_citations,
      metadata: query.metadata,
      inserted_at: query.inserted_at && DateTime.to_iso8601(query.inserted_at)
    }
  end
end
