defmodule Synapse.Signal do
  @moduledoc """
  Canonical registry of signal topics and their schemas.

  Provides helpers for resolving topics to wire-level types, validating
  payloads, and mapping incoming `Jido.Signal` structs to strongly typed data.
  """

  alias Synapse.Signal.{
    ReviewRequest,
    ReviewResult,
    ReviewSummary,
    SpecialistReady
  }

  @type topic ::
          :review_request
          | :review_result
          | :review_summary
          | :specialist_ready

  @topics %{
    review_request: %{type: "review.request", schema: ReviewRequest},
    review_result: %{type: "review.result", schema: ReviewResult},
    review_summary: %{type: "review.summary", schema: ReviewSummary},
    specialist_ready: %{type: "review.specialist_ready", schema: SpecialistReady}
  }

  @topics_by_type Map.new(@topics, fn {topic, %{type: type}} -> {type, topic} end)

  @doc """
  Returns the wire-format type for the given topic.
  """
  @spec type(topic()) :: String.t()
  def type(topic) do
    @topics
    |> Map.fetch!(topic)
    |> Map.fetch!(:type)
  end

  @doc """
  Resolves a type string (e.g., \"review.request\") into the canonical topic atom.
  """
  @spec topic_from_type(String.t()) :: {:ok, topic()} | :error
  def topic_from_type(type) do
    case Map.fetch(@topics_by_type, type) do
      {:ok, topic} -> {:ok, topic}
      :error -> :error
    end
  end

  @doc """
  Validates a payload for the provided topic and returns the normalized map.
  """
  @spec validate!(topic(), map()) :: map()
  def validate!(topic, payload) when is_map(payload) do
    @topics
    |> Map.fetch!(topic)
    |> Map.fetch!(:schema)
    |> apply(:validate!, [payload])
  end

  @doc """
  Lists all known topics.
  """
  @spec topics() :: [topic()]
  def topics, do: Map.keys(@topics)
end
