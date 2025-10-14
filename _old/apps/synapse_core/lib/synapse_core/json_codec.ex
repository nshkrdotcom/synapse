defmodule SynapseCore.JSONCodec do
  # Use a library like 'Jason' for JSON encoding/decoding.
  def encode(data) do
    Jason.encode!(data)
  end

  def decode(json_string) do
    Jason.decode!(json_string)
  end
end
