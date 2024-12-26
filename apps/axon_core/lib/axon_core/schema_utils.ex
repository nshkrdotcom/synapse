defmodule AxonCore.SchemaUtils do
  @moduledoc """
  Utilities for handling JSON Schema translation and validation in Axon.

 This module provides functions for converting Elixir data structures to JSON
  Schema and vice-versa. It also includes a function for validating data against
  a JSON Schema.
  """

  @type json_schema :: map()

 @doc """
  Converts an Elixir data structure (representing a type) to a JSON Schema.

  Handles basic types, lists, maps, and nested structures.
  """
  @spec elixir_to_json_schema(any()) :: json_schema()
  def elixir_to_json_schema(type) when is_binary(type) or is_atom(type) do
    json_type =
      case type do
        "string" -> "string"
        "integer" -> "integer"
        "boolean" -> "boolean"
        "number" -> "number"
        "null" -> "null"
        :string -> "string"
        :integer -> "integer"
        :boolean -> "boolean"
        :number -> "number"
        :null -> "null"
        _ -> "string"  # Default to string if type is unknown or a binary
      end

    %{"type" => json_type}
  end

  def elixir_to_json_schema(type) when is_list(type) do
    case length(type) do
      0 -> %{"type" => "array", "items" => %{}}
      _ -> %{"type" => "array", "items" => elixir_to_json_schema(hd(type))}
    end
  end

  def elixir_to_json_schema(type) when is_map(type) do
    properties =
      for {key, val} <- type, into: %{} do
        {to_string(key), elixir_to_json_schema(val)}
      end

    required_keys =
      for {key, val} <- type,
          is_tuple(val) and elem(val, 1) == :required,
          into: [] do
        to_string(key)
      end

    schema = %{
      "type" => "object",
      "properties" => properties,
      "required" => required_keys
    }

    # Remove "required" key if it's empty
    if required_keys == [] do
      Map.delete(schema, "required")
    else
      schema
    end


    ## Remove "required" key if it's empty, otherwise add it
    #if required_keys == [], do: schema, else: Map.put(schema, "required", required_keys)
  end

  def elixir_to_json_schema(type) do
    raise ArgumentError, "Unsupported type for JSON Schema conversion: #{inspect(type)}"
  end

  @doc """
  Converts a JSON Schema to a basic Elixir type representation.

  This is a simplified example and would need to be expanded to handle
  more complex schemas and edge cases.
  """
  @spec json_schema_to_elixir_type(json_schema()) :: any()
  def json_schema_to_elixir_type(schema) do
    case schema do
      %{"type" => "string"} -> :string
      %{"type" => "integer"} -> :integer
      %{"type" => "boolean"} -> :boolean
      %{"type" => "number"} -> :number
      %{"type" => "array", "items" => items_schema} -> [json_schema_to_elixir_type(items_schema)]
      %{"type" => "object", "properties" => properties} ->
        for {key, val} <- properties, into: %{} do
          {String.to_atom(key), json_schema_to_elixir_type(val)}
        end
      %{"type" => "null"} -> nil
      _ -> :any  # Fallback for unsupported types
    end
  end

  @doc """
  Validates a data structure against a JSON Schema.

  Uses `jason_schema` for validation.
  """
  @spec validate(json_schema(), any()) :: :ok | {:error, any()}
  def validate(schema, data) do
    case Jason.Schema.validate(schema, data) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end



  # Add more functions as needed for:
  # - Converting Pydantic models to JSON Schema (if necessary)
  # - Handling schema composition and references
