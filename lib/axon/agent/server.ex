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

  def via_tuple(name) do
    {:via, Registry, {Axon.AgentRegistry, name}}
  end

  @impl true
  def init(opts) do
    Logger.info("Initializing agent server with options: #{inspect(opts)}")

    state =
      opts
      |> Enum.into(%{})
      |> Map.put_new(:port, opts[:port] || get_free_port())

    Logger.info("Agent server state: #{inspect(state)}")

    # Start Python agent
    port = start_python_agent(state)
    state = Map.put(state, :port_ref, port)

    # Give the Python process a moment to start and check its output
    Process.sleep(2000)

    # Try to ping the agent to verify it's running
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    case HTTPClient.post(endpoint, headers, JSONCodec.encode!(%{message: "ping"})) do
      {:ok, _} ->
        Logger.info("Successfully connected to Python agent")
        {:ok, state}
      {:error, reason} ->
        Logger.error("Failed to connect to Python agent: #{inspect(reason)}")
        Port.close(port)
        {:stop, :python_agent_not_responding}
    end
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

  @impl true
  def handle_info({port, {:data, data}}, %{port_ref: port} = state) when is_port(port) do
    # Split data into lines and log each one
    String.split(data, "\n")
    |> Enum.each(fn line ->
      unless line == "", do: Logger.info("Python: #{line}")
    end)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port_ref: port} = state) when is_port(port) do
    Logger.error("Python process exited with status #{status}")
    {:stop, :python_process_exited, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp start_python_agent(%{python_module: module, model: model, port: port} = state) do
    python_cmd = System.find_executable("python3") || System.find_executable("python")
    unless python_cmd, do: raise "Python executable not found"

    working_dir = Path.absname("apps/axon_python/src")
    module_path = module

    # Ensure extra_env is a list of string tuples
    extra_env =
      case state[:extra_env] do
        nil -> []
        extra when is_list(extra) ->
          Enum.map(extra, fn
            {k, v} when is_atom(k) -> {Atom.to_string(k), to_string(v)}
            {k, v} when is_binary(k) -> {k, to_string(v)}
          end)
        _ ->
          raise ArgumentError,
                "extra_env must be a keyword list or a list of two-element tuples"
      end

    # Merge extra_env with our base env, ensuring no duplicates
    base_env = [
      {"PYTHONPATH", working_dir},
      {"AXON_PYTHON_AGENT_MODEL", model},
      {"AXON_PYTHON_AGENT_PORT", Integer.to_string(port)}
    ]

    env = Enum.uniq_by(extra_env ++ base_env, fn {k, _} -> k end)

    Logger.info("""
    Starting Python agent:
    Port: #{port}
    Python cmd: #{python_cmd}
    Working dir: #{working_dir}
    Module path: #{module_path}
    Environment:
    #{Enum.map_join(env, "\n", fn {k, v} -> "        #{k}=#{v}" end)}
    """)

    full_path = working_dir <> "/axon_python/agent_wrapper.py"
    Logger.info("Port options 1: #{inspect(module_path, pretty: true)}")
    args_1 = [full_path, "-u", "-m"]

    port_opts = [
      :binary,
      :exit_status,
      {:cd, working_dir},
      {:env, env},
      args: args_1
    ]    # Add args: separately
    #Logger.info("Port options 1: #{inspect(port_opts_1, pretty: true)}")
    try do
      Logger.info("Attempting to open port with test script...")
      port = Port.open({:spawn_executable, python_cmd}, args: args_1)
      Logger.info("Successfully opened port with test script: #{inspect(port)}")

      # If successful, proceed with the actual agent
      Port.close(port)  # Close the test port
      port

    rescue
      e ->
        Logger.error("""
        Failed to open port with options:
          Command: #{python_cmd}
          Options: #{inspect(port_opts, pretty: true)}
          Error: #{inspect(e, pretty: true)}
        """)
        reraise e, __STACKTRACE__
    end
  end

  defp get_free_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [
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
