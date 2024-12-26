defmodule AxonCore.ToolUtils do
  @moduledoc """
  Utilities for handling tool definitions and potentially dynamic function calls
  for Elixir-based tools in Axon.
  """

  alias AxonCore.SchemaUtils

  @type tool_handler :: {:elixir, function()} | {:python, module: String.t(), function: String.t()}

  @type tool_definition :: %{
          name: String.t(),
          description: String.t(),
          parameters: map(), # JSON Schema for parameters
          handler: tool_handler()
        }

  @doc """
  Converts an Elixir tool definition to a JSON Schema representation
  compatible with pydantic-ai.
  """
  @spec to_json_schema(tool_definition()) :: map()
  def to_json_schema(%{name: name, description: description, parameters: parameters} = _tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => description,
        "parameters" => parameters
      }
    }
  end

  @doc """
  Calls an Elixir tool function dynamically.

  ## Parameters

    - `fun`: The function to call.
    - `args`: The arguments to pass to the function.
  """
  @spec call_elixir_tool(function(), list()) :: {:ok, any()} | {:error, any()}
  def call_elixir_tool(fun, args) do
    try do
      {:ok, apply(fun, args)}
    catch
      kind, reason ->
        {:error, {kind, reason, __STACKTRACE__}}
    end
  end

  @doc """
  Extracts tool definitions from an agent configuration.

  ## Parameters

    - `config`: The agent configuration map.

  ## Returns

  A list of tool definitions with handlers set for Python functions.
  """
  @spec extract_tools(map()) :: list(tool_definition())
  def extract_tools(config) do
    config[:tools]
    |> Enum.map(fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: SchemaUtils.elixir_to_json_schema(tool.parameters),
        # handler: tool.handler
        # Assuming all tools are Python-based for this example
        handler: {:python, module: config[:module], function: tool.name}
      }
    end)
  end

  @doc """
  Serializes the arguments of a tool call to JSON, based on the tool definition.

  ## Parameters

  - `tool_def`: The tool definition map.
  - `args`: The arguments to serialize.

  ## Returns

  A JSON string representing the serialized arguments, or an error tuple if serialization fails.
  """
  @spec serialize_tool_args(tool_definition(), map()) :: {:ok, binary()} | {:error, any()}
  def serialize_tool_args(tool_def, args) do
    try do
      # Validate the arguments against the schema
      case SchemaUtils.validate(tool_def.parameters, args) do
        :ok ->
          # Encode the arguments to JSON
          {:ok, Jason.encode!(args)}

        {:error, reason} ->
          {:error, reason}
      end
    catch
      e ->
        {:error, {:serialization_error, e}}
    end
  end

  # Add more functions as needed for:
  # - Validating tool definitions
  # - Generating Python stubs for Elixir tools (if needed)






end
