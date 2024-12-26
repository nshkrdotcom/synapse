defmodule AxonCore.PydanticAgentProcess do
  @moduledoc """
  GenServer process that manages a Python-based pydantic-ai agent.
  Handles lifecycle, message passing, and error handling.
  """
  use GenServer
  require Logger

  alias AxonCore.{HTTPClient, JSONCodec}

  @type agent_config :: %{
    name: String.t(),
    python_module: String.t(),
    model: String.t(),
    port: integer(),
    system_prompt: String.t(),
    tools: list(map()),
    result_type: map(),
    extra_env: keyword()
  }

  @type state :: %{
    name: String.t(),
    python_module: String.t(),
    model: String.t(),
    port: integer(),
    base_url: String.t(),
    message_history: list(map()),
    model_settings: map(),
    system_prompt: String.t(),
    tools: list(map()),
    result_type: map(),
    extra_env: keyword()
  }

  @default_timeout 60_000

  # Client API

  @doc """
  Starts an agent process with the given configuration.
  """
  @spec start_link(agent_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  @doc """
  Sends a message to the agent and awaits response.
  """
  @spec run(String.t(), String.t(), list(), map()) :: {:ok, map()} | {:error, term()}
  def run(agent_name, prompt, message_history \\ [], model_settings \\ %{}) do
    GenServer.call(agent_name, {:run, prompt, message_history, model_settings}, @default_timeout)
  end

  @doc """
  Streams responses from the agent.
  """
  @spec run_stream(String.t(), String.t(), list(), map()) :: {:ok, pid()} | {:error, term()}
  def run_stream(agent_name, prompt, message_history \\ [], model_settings \\ %{}) do
    GenServer.call(agent_name, {:run_stream, prompt, message_history, model_settings}, @default_timeout)
  end

  @doc """
  Calls a specific tool on the agent.
  """
  @spec call_tool(String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(agent_name, tool_name, args) do
    GenServer.call(agent_name, {:call_tool, tool_name, args}, @default_timeout)
  end

  # Server Callbacks

  @impl true
  def init(config) do
    state = %{
      name: config.name,
      python_module: config.python_module,
      model: config.model,
      port: config.port,
      base_url: "http://localhost:#{config.port}",
      message_history: [],
      model_settings: %{},
      system_prompt: config.system_prompt,
      tools: config.tools,
      result_type: config.result_type,
      extra_env: config.extra_env
    }

    # Register agent with Python wrapper
    case register_agent(state) do
      :ok -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:run, prompt, message_history, model_settings}, _from, state) do
    case HTTPClient.post("#{state.base_url}/run", %{
      prompt: prompt,
      message_history: message_history,
      model_settings: model_settings,
      system_prompt: state.system_prompt,
      tools: state.tools,
      result_type: state.result_type
    }) do
      {:ok, response} ->
        {:reply, process_response(response), %{state | message_history: message_history}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:run_stream, prompt, message_history, model_settings}, {pid, _} = from, state) do
    case HTTPClient.post_stream("#{state.base_url}/run/stream", %{
      prompt: prompt,
      message_history: message_history,
      model_settings: model_settings,
      system_prompt: state.system_prompt,
      tools: state.tools,
      result_type: state.result_type
    }) do
      {:ok, stream_pid} ->
        # Forward stream events to caller
        spawn_link(fn -> forward_stream(stream_pid, pid) end)
        {:reply, {:ok, stream_pid}, %{state | message_history: message_history}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:call_tool, tool_name, args}, _from, state) do
    case HTTPClient.post("#{state.base_url}/tool_call", %{
      tool_name: tool_name,
      args: args
    }) do
      {:ok, response} ->
        {:reply, process_tool_response(response), state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private Functions

  defp register_agent(state) do
    HTTPClient.post("#{state.base_url}/agents", %{
      agent_id: state.name,
      model: state.model,
      system_prompt: state.system_prompt,
      tools: state.tools,
      result_type: state.result_type
    })
  end

  defp process_response(%{"result" => result, "messages" => messages, "usage" => usage}) do
    {:ok, %{
      result: result,
      messages: messages,
      usage: usage
    }}
  end

  defp process_response(%{"error" => error}), do: {:error, error}

  defp process_tool_response(%{"result" => result}), do: {:ok, result}
  defp process_tool_response(%{"error" => error}), do: {:error, error}

  defp forward_stream(stream_pid, target_pid) do
    receive do
      {:chunk, chunk} ->
        send(target_pid, {:chunk, chunk})
        forward_stream(stream_pid, target_pid)
      {:end_stream} ->
        send(target_pid, {:end_stream})
      {:error, reason} ->
        send(target_pid, {:error, reason})
    end
  end
end
