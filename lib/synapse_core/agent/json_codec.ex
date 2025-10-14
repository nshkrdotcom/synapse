defmodule SynapseCore.Agent.JSONCodec do
  @moduledoc """
  JSON encoding/decoding utilities using Jason.
  """

  def encode!(data) do
    Jason.encode!(data)
  end

  def decode!(json) when is_binary(json) do
    Jason.decode!(json)
  end
end
