defmodule Axon.Agent.Server do
  @moduledoc """
  Agent.Server is the GenServer responsible for managing the state of a
  single agent. It handles the communication with the agent and keeps
  track of the agent's configuration, state, and chat history.
  """
  use GenServer
  require Logger

  alias Axon.Agent.HTTPClient
  alias Axon.Agent.JSONCodec

  def start_link(opts) do
    name = opts[:name] || raise ArgumentError, "name is required"
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @impl true
  def init(opts) do
    state =
      opts
      |> Enum.into(%{})
      |> Map.put_new(:port, opts[:port] || get_free_port())

    # Start Python agent if port wasn't provided
    if !opts[:port] do
      start_python_agent(state)
    end

    # Create a process group for the agent
    :ok = :pg.join(state.name, self())

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    case HTTPClient.post(endpoint, headers, JSONCodec.encode!(message)) do
      {:ok, response} ->
        {:reply, {:ok, JSONCodec.decode!(response.body)}, state}
      {:error, reason} ->
        Logger.error("Failed to send message to agent: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  defp start_python_agent(%{python_module: module, model: model, port: port} = state) do
    python_cmd = System.get_env("PYTHON_EXEC", "python")
    spawn_cmd = "#{python_cmd} -u -m axon_python.agent_wrapper"

    env = [
      {"PYTHONPATH", "./"},
      {"AXON_PYTHON_AGENT_MODEL", model} | 
      (state[:extra_env] || [])
    ]

    Port.open(
      {:spawn_executable, spawn_cmd},
      [
        {:args, [module, Integer.to_string(port), model]},
        {:cd, "apps/axon_python/src"},
        {:env, env},
        :binary,
        :use_stdio,
        :stderr_to_stdout,
        :hide
      ]
    )
  end

  defp via_tuple(agent_name) when is_binary(agent_name) do
    {:via, :pg, agent_name}
  end

  defp get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [
      :binary, 
      packet: :raw, 
      reuseaddr: true, 
      active: false
    ])
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end
end
