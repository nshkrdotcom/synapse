defmodule Axon.Agent.Server do
  @moduledoc """
  Agent.Server is the GenServer responsible for managing the state of a
  single agent. It handles the communication with the agent and keeps
  track of the agent's configuration, state, and chat history.
  """
  use GenServer

  alias Axon.Agent.HTTPClient
  alias Axon.Agent.JSONCodec

  @default_timeout 60_000

  @doc """
  Starts an agent server process.

  ## Parameters

    - `opts`: A list of options.
      - `name`: The name of the agent.
      - `module`: The module where the Python agent is defined.
      - `model`: The LLM model to use.
      - `port`: The port number for the agent's HTTP server.
      - `extra_env`: Extra environment variables to pass to the Python agent process.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:name]))
  end

  @doc """
  Returns the PID of the agent process associated with the given agent name.
  """
  def pid(agent_name) when is_binary(agent_name) do
    case :pg.get_members(agent_name) do
      [] ->
        nil

      [pid | _] ->
        pid
    end
  end

  @doc """
  Sends a message to the Python agent and awaits the response.

  ## Parameters

    - `agent_name`: The name of the agent.
    - `message`: The message to send.

  ## Returns

  Either `{:ok, response}` or `{:error, reason}`.
  """
  def send_message(agent_name, message) do
    GenServer.call(via_tuple(agent_name), {:send_message, message}, @default_timeout)
  end

  @impl true
  def init(opts) do
    # Convert opts to a map for easier access
    state =
      opts
      |> Enum.into(%{})
      |> Map.put(:port, start_python_agent(opts))

    # Create a process group for the agent
    :ok = :pg.join(state[:name], self())

    {:ok, state}
  end

  defp start_python_agent(opts) do
    # Start the Python agent process using Ports
    # Pass configuration as environment variables or command-line arguments
    port = get_free_port()

    python_command =
      if System.get_env("PYTHON_EXEC") != nil do
        System.get_env("PYTHON_EXEC")
      else
        "python"
      end

    {:ok, _} = Application.ensure_all_started(:os_mon)
    spawn_port = "#{python_command} -u -m axon_python.agent_wrapper"

    Port.open(
      {:spawn_executable, spawn_port},
      [
        {:args,
         [
           opts[:python_module] || raise("--python_module is required"),
           Integer.to_string(port),
           opts[:model] || raise("--model is required")
         ]},
        {:cd, "apps/axon_python/src"},
        {:env, ["PYTHONPATH=./", "AXON_PYTHON_AGENT_MODEL=#{opts[:model]}" | opts[:extra_env]]},
        :binary,
        :use_stdio,
        :stderr_to_stdout,
        :hide
      ]
    )

    port
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    # Send an HTTP request to the Python agent
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(message)) do
      # Process the response
      {:reply, {:ok, JSONCodec.decode(response.body)}, state}
    else
      {:error, reason} ->
        # Handle error, potentially restart the Python process using the supervisor
        {:reply, {:error, reason}, state}
    end
  end

  # ... (other handle_call and handle_info for different types of requests)

  defp via_tuple(agent_name) when is_binary(agent_name) do
    {:via, :pg, agent_name}
  end

  defp get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, reuseaddr: true, active: false])
    {_, port} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end
end
