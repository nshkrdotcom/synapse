defmodule SynapseCore.PydanticJSONCodec do
  @moduledoc """
  JSON encoding/decoding utilities specifically for pydantic-ai integration.
  Handles datetime serialization and custom types.
  """

  @doc """
  Encodes a term to JSON string.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(term) do
    Jason.encode(term, pretty: true)
  end

  @doc """
  Decodes a JSON string to a term.
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, term()}
  def decode(json) do
    Jason.decode(json)
  end

  @doc """
  Encodes a term to JSON string, raising on error.
  """
  @spec encode!(term()) :: String.t()
  def encode!(term) do
    Jason.encode!(term, pretty: true)
  end

  @doc """
  Decodes a JSON string to a term, raising on error.
  """
  @spec decode!(String.t()) :: term()
  def decode!(json) do
    Jason.decode!(json)
  end

  @doc """
  Converts a map with string keys to one with atom keys.
  Only converts known keys to avoid atom table pollution.
  """
  @spec atomize_keys(map(), [atom()]) :: map()
  def atomize_keys(map, allowed_keys) when is_map(map) do
    Map.new(map, fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_existing_atom(key), else: key
      if atom_key in allowed_keys do
        {atom_key, value}
      else
        {key, value}
      end
    end)
  end

  @doc """
  Converts datetime strings in a map to DateTime structs.
  """
  @spec convert_datetimes(map()) :: map()
  def convert_datetimes(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {key, datetime}
          _error -> {key, value}
        end
      {key, value} when is_map(value) ->
        {key, convert_datetimes(value)}
      {key, value} when is_list(value) ->
        {key, Enum.map(value, &convert_datetimes_in_list/1)}
      pair ->
        pair
    end)
  end

  defp convert_datetimes_in_list(value) when is_map(value), do: convert_datetimes(value)
  defp convert_datetimes_in_list(value), do: value
end
