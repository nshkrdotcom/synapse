defmodule SynapseCore.JSONCodec do
  @moduledoc """
  JSON encoding/decoding utilities using Jason.
  """

  @doc """
  Encodes data to JSON string.
  """
  def encode(data) do
    Jason.encode(data)
  end

  @doc """
  Decodes JSON string to Elixir term.
  """
  def decode(json) when is_binary(json) do
    Jason.decode(json)
  end

  def encode!(data) do
    Jason.encode!(data)
  end

  def decode!(json) when is_binary(json) do
    Jason.decode!(json)
  end
end
