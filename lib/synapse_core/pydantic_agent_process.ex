defmodule SynapseCore.PydanticAgentProcess do
  use GenServer
  require Logger

  alias SynapseCore.HTTPClient

  @doc """
  Starts an agent process with the given configuration.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Streams responses from the agent.
  """
  def run_stream(agent_name, prompt, message_history \\ [], model_settings \\ %{}) do
    GenServer.call(agent_name, {:run_stream, prompt, message_history, model_settings})
  end

  @impl true
  def init(opts) do
    state = %{
      base_url: opts[:base_url] || "http://localhost:8000",
      message_history: []
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:run_stream, prompt, message_history, model_settings}, _from, state) do
    case HTTPClient.post_stream("#{state.base_url}/run/stream", %{
      "prompt" => prompt,
      "message_history" => message_history,
      "model_settings" => model_settings
    }) do
      {:ok, stream_pid} ->
        {:reply, {:ok, stream_pid}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
