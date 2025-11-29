defmodule Synapse.Signal do
  @moduledoc """
  Canonical registry of signal topics and their schemas.

  Delegates to `Synapse.Signal.Registry` so topics can be declared via
  configuration or registered at runtime.
  """

  alias Synapse.Signal.Registry

  @type topic :: atom()

  @doc """
  Returns the wire-format type for the given topic.
  """
  @spec type(topic()) :: String.t()
  defdelegate type(topic), to: Registry

  @doc """
  Lists all known topics.
  """
  @spec topics() :: [topic()]
  defdelegate topics(), to: Registry, as: :list_topics

  @doc """
  Validates a payload for the provided topic and returns the normalized map.
  """
  @spec validate!(topic(), map()) :: map()
  defdelegate validate!(topic, payload), to: Registry

  @doc """
  Resolves a type string (e.g., \"review.request\") into the canonical topic atom.
  """
  @spec topic_from_type(String.t()) :: {:ok, topic()} | :error
  defdelegate topic_from_type(type), to: Registry

  @doc """
  Registers a topic at runtime.
  """
  @spec register_topic(topic(), keyword()) :: :ok | {:error, term()}
  defdelegate register_topic(topic, config), to: Registry
end
