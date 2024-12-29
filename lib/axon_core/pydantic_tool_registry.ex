defmodule AxonCore.PydanticToolRegistry do
  @moduledoc """
  Registry for managing and validating tools that can be used by pydantic-ai agents.
  """
  
  use GenServer
  require Logger

  # Types

  @type tool_config :: %{
    name: String.t(),
    description: String.t(),
    parameters: map(),
    handler: {module(), atom()} | function()
  }

  @type state :: %{
    tools: %{String.t() => tool_config()}
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new tool with the registry.
  """
  @spec register_tool(tool_config()) :: :ok | {:error, term()}
  def register_tool(tool_config) do
    GenServer.call(__MODULE__, {:register_tool, tool_config})
  end

  @doc """
  Gets a tool configuration by name.
  """
  @spec get_tool(String.t()) :: {:ok, tool_config()} | {:error, :not_found}
  def get_tool(name) do
    GenServer.call(__MODULE__, {:get_tool, name})
  end

  @doc """
  Lists all registered tools.
  """
  @spec list_tools() :: [tool_config()]
  def list_tools do
    GenServer.call(__MODULE__, :list_tools)
  end

  @doc """
  Executes a tool with the given arguments.
  """
  @spec execute_tool(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_tool(name, args) do
    GenServer.call(__MODULE__, {:execute_tool, name, args})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{tools: %{}}}
  end

  @impl true
  def handle_call({:register_tool, tool_config}, _from, state) do
    with :ok <- validate_tool_config(tool_config) do
      new_state = put_in(state.tools[tool_config.name], tool_config)
      {:reply, :ok, new_state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to register tool: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_tool, name}, _from, state) do
    case Map.fetch(state.tools, name) do
      {:ok, tool} -> {:reply, {:ok, tool}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    {:reply, Map.values(state.tools), state}
  end

  @impl true
  def handle_call({:execute_tool, name, args}, _from, state) do
    with {:ok, tool} <- Map.fetch(state.tools, name),
         {:ok, validated_args} <- validate_args(tool.parameters, args),
         {:ok, result} <- execute_handler(tool.handler, validated_args) do
      {:reply, {:ok, result}, state}
    else
      :error ->
        {:reply, {:error, :tool_not_found}, state}
      {:error, reason} = error ->
        Logger.error("Tool execution failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  # Private Functions

  defp validate_tool_config(config) do
    required_keys = [:name, :description, :parameters, :handler]
    
    with :ok <- validate_required_keys(config, required_keys),
         :ok <- validate_handler(config.handler),
         :ok <- validate_parameters_schema(config.parameters) do
      :ok
    end
  end

  defp validate_required_keys(config, keys) do
    case Enum.find(keys, &(not Map.has_key?(config, &1))) do
      nil -> :ok
      key -> {:error, {:missing_key, key}}
    end
  end

  defp validate_handler({module, function}) when is_atom(module) and is_atom(function) do
    if function_exported?(module, function, 1) do
      :ok
    else
      {:error, {:invalid_handler, :function_not_exported}}
    end
  end
  defp validate_handler(fun) when is_function(fun, 1), do: :ok
  defp validate_handler(_), do: {:error, {:invalid_handler, :invalid_type}}

  defp validate_parameters_schema(schema) when is_map(schema) do
    # Basic JSON Schema validation
    required_keys = ["type", "properties"]
    case validate_required_keys(schema, required_keys) do
      :ok -> :ok
      error -> {:error, {:invalid_schema, error}}
    end
  end
  defp validate_parameters_schema(_), do: {:error, {:invalid_schema, :not_a_map}}

  defp validate_args(schema, args) do
    # TODO: Implement proper JSON Schema validation
    # For now, just ensure all required fields are present
    required = schema["required"] || []
    case Enum.find(required, &(not Map.has_key?(args, &1))) do
      nil -> {:ok, args}
      missing -> {:error, {:missing_argument, missing}}
    end
  end

  defp execute_handler({module, function}, args) do
    try do
      result = apply(module, function, [args])
      {:ok, result}
    rescue
      e -> {:error, {:execution_error, Exception.message(e)}}
    end
  end
  defp execute_handler(fun, args) when is_function(fun, 1) do
    try do
      result = fun.(args)
      {:ok, result}
    rescue
      e -> {:error, {:execution_error, Exception.message(e)}}
    end
  end
end
