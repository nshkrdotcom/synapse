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

  A list of tool definitions.
  """
  @spec extract_tools(map()) :: list(tool_definition())
  def extract_tools(config) do
    config[:tools]
    |> Enum.map(fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: SchemaUtils.elixir_to_json_schema(tool.parameters),
        handler: tool.handler
      }
    end)
  end

  # Add more functions as needed for:
  # - Validating tool definitions
  # - Generating Python stubs for Elixir tools (if needed)
end
