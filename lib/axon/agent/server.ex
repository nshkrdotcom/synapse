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
  alias AxonCore.PythonEnvManager

  @default_model "default"
  @default_python_module "agents.example_agent"

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    #:ok = AxonCore.PythonEnvManager.ensure_env!()
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
      |> Map.put_new(:model, @default_model)
      |> Map.put_new(:python_module, @default_python_module)
     # |> Map.put_new(:port, 5427)

    Logger.info("Agent server state: #{inspect(state)}")

    case start_python_agent(state) do
      {port_ref, _port} when is_port(port_ref) ->
        state = Map.put(state, :port_ref, port_ref)

        # Give the Python process a moment to start
        Logger.info("sleeping for 2000 here...")
        Process.sleep(2000)
        Logger.info("Done sleep...")

        # Try to ping the agent
        endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
        headers = [{"Content-Type", "application/json"}]

        case HTTPClient.post(endpoint, headers, JSONCodec.encode!(%{message: "ping"})) do
          {:ok, _} ->
            Logger.info("Successfully connected to Python agent")
            {:ok, state}
          {:error, reason} ->
            Logger.error("Failed to connect to Python agent: #{inspect(reason)}")
            Port.close(port_ref)
            {:stop, :python_agent_not_responding}
        end
      _ ->
        {:stop, :python_agent_start_failed}
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
  def handle_info({port, {:data, data}}, %{port_ref: port_ref} = state) when port == port_ref do
    Logger.info("Received data from Python process")
    String.split(data, "\n")
    |> Enum.each(fn line ->
      unless line == "", do: Logger.info("Python: #{line}")
    end)
    {:noreply, state}
  end

  # Handle Port exit
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port_ref: port_ref} = state) when port == port_ref do
    Logger.error("Python process exited with status #{status}")
    {:stop, :python_process_exited, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp start_python_agent(%{
    python_module: module,
    model: model,
    port: port,
    name: agent_id
  }) do
    Logger.info("Starting Python agent with module: #{inspect(module)}, model: #{inspect(model)}, port: #{inspect(port)}, agent_id: #{inspect(agent_id)}")
    # python_cmd = AxonCore.PythonEnvManager.python_path()
    #working_dir = Path.absname("apps/axon_python/src")
    start_agent_script_path =
    Path.absname(
      Path.join([
        File.cwd!(),
        "apps",
        "axon_python",
        "scripts",
        "start_agent.sh"
      ])
    )
    env_vars = PythonEnvManager.env_vars()
    port_p = "#{inspect(port)}"
    agent_id_p = "#{inspect(agent_id)}"
    _virtual_env_path = Enum.find_value(env_vars, fn {key, venv_path} ->
      if key == "VIRTUAL_ENV" do
        Logger.info("Executing command: /bin/bash #{inspect(start_agent_script_path)} #{inspect(venv_path)} #{inspect(module)} #{inspect(port_p)} #{inspect(model)} #{inspect(agent_id_p)}")
        port_ref = Port.open(
          {:spawn_executable, "/bin/bash"},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            :hide,
            :use_stdio,
            args: [start_agent_script_path, venv_path, module, port_p, model, agent_id_p]
          ]
        )
        listen_for_output(port_ref)
        Logger.info("Started Python agent on port_ref: #{inspect(port_ref)} port:#{inspect(port)}")
        Logger.info("Sleeping for 2000 ms...")
        Process.sleep(2000)  # Allow the Python agent to start up
        Logger.info("\n\nDone sleeping...")
        {port_ref, port}
      else
        nil
      end
    end)
  end

  defp listen_for_output(port) do
    # Continuously listen for data or other messages from the port
    receive do
      {^port, {:data, data}} ->
        Logger.info("Port Output: #{data}")
        listen_for_output(port)

      {^port, :closed} ->
        IO.puts("Port closed")
        {:noreply, nil}
    end
  end


end
