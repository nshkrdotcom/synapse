defmodule SynapseCore.ToolUtils do
  @moduledoc """
  Utilities for handling tool definitions and potentially dynamic function calls
  for Elixir-based tools in Synapse.
  """

  alias SynapseCore.SchemaUtils

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
  Calls an Elixir function dynamically, identified by its module and function name.

  This function provides a mechanism for Elixir code to invoke other Elixir functions
  based on information received from the Python agent. It's crucial for enabling Elixir-based
  tools within the Synapse framework.

  ## Parameters

  - `module`: The name of the module where the function is defined (e.g., `MyModule`).
  - `function_name`: The name of the function to call (e.g., `my_function`).
  - `args`: A list of arguments to pass to the function.

  ## Returns

  - `{:ok, result}` if the function call is successful. `result` is the return value of the function.
  - `{:error, reason}` if an error occurs during the function call. `reason` will contain details about the error.

  ## Security Considerations

  This function uses `apply/3` to dynamically call functions based on their module and function name.
  **Be extremely cautious about the source of `module` and `function_name` to prevent arbitrary code execution.**
  Only use this function with trusted inputs, ideally from a predefined set of allowed tools.

  Do not directly expose this function to user input without proper sanitization and validation.

  ## Example

  To call a function named `add_numbers` in a module named `MyModule` with arguments `[1, 2]`:

  ```elixir
  case SynapseCore.ToolUtils.call_elixir_tool(MyModule, :add_numbers, [1, 2]) do
    {:ok, result} ->
      # Handle successful result
      IO.inspect(result) # Output: 3

    {:error, reason} ->
      # Handle error
      IO.inspect(reason)
  end
  """
  @spec call_elixir_tool(function(), list()) :: {:ok, any()} | {:error, any()}
  def call_elixir_tool(fun, args) do
    try do
      # Convert atom function_name to string for apply
      function_name_str = Atom.to_string(function_name)
      # Dynamically call the function using apply
      {:ok, apply(module, String.to_atom(function_name_str), args)}
      #{:ok, apply(fun, args)}
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
