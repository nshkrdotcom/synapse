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
    Logger.info("#{inspect(opts)}")
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

    Logger.info("Agent server state: #{inspect(state)}")

    case start_python_agent(state) do
      {:ok, ext} ->
        #Task.start_link(fn -> listen_for_output(ext) end)
        endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
        headers = [{"Content-Type", "application/json"}]
        {:ok, ext}
        # case HTTPClient.post(endpoint, headers, JSONCodec.encode!(%{message: "ping"})) do
        #   {:ok, _} ->
        #     Logger.info("Successfully connected to Python agent")
        #     {:ok, ext}
        #   {:error, reason} ->
        #     Logger.error("Failed to connect to Python agent: #{inspect(reason)}")
        #     Port.close(ext)
        #     {:stop, :python_agent_not_responding}
        # end
      _ ->
        {:stop, :python_agent_start_failed}
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, ext) do
    endpoint = "http://localhost:#{ext.port}/agents/#{ext.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    case HTTPClient.post(endpoint, headers, JSONCodec.encode!(message)) do
      {:ok, response} ->
        {:reply, {:ok, JSONCodec.decode!(response.body)}, ext}
      {:error, reason} ->
        Logger.error("Failed to send message to agent: #{inspect(reason)}")
        {:reply, {:error, reason}, ext}
    end
  end

  @impl true
  #def handle_info({port, {:data, data}}, %{port_ref: port_ref} = ext) when port == port_ref do
  def handle_info({msg, {:data, data}}, ext) when msg == ext do
      #Logger.info("")
    String.split(data, "\n")
    |> Enum.each(fn line ->
      unless line == "", do: Logger.info("Received data from Python process: #{line}")
    end)
    {:noreply, ext}
  end

  # Handle Port exit
  @impl true
  def handle_info({msg, {:exit_status, status}}, ext) when msg == ext do
    Logger.error("Python process exited with status: [#{status}]")
    {:stop, :python_process_exited, ext}
  end

  @impl true
  def handle_info(msg, ext) do
    Logger.info("Unexpected message: #{inspect(msg)}")
    {:noreply, ext}
  end

  defp start_python_agent(%{
    python_module: module,
    model: model,
    port: port_number,
    name: agent_id
  }) do
    Logger.info("Starting Python agent with module: #{inspect(module)}, model: #{inspect(model)}, port: #{inspect(port_number)}, agent_id: #{inspect(agent_id)}")
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
    port_p = "#{inspect(port_number)}"
    agent_id_p = "#{inspect(agent_id)}"
    {_, venv_path} = List.first(env_vars) ##TODO: cleanup
    #Logger.info("#{inspect(venv_path)}")
    Logger.info("Executing command: /bin/bash #{inspect(start_agent_script_path)} #{inspect(venv_path)} #{inspect(module)} #{inspect(port_p)} #{inspect(model)} #{inspect(agent_id_p)}")
    #command = "#{inspect(start_agent_script_path)} #{inspect(venv_path)} #{inspect(module)} #{inspect(port_p)} #{inspect(model)} #{inspect(agent_id_p)}"
    #ext = Exile.stream!(["/bin/bash", command], stderr: :consume)
    ext = Port.open(
      {:spawn_executable, "/bin/bash"},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: [start_agent_script_path, venv_path, module, port_p, model, agent_id_p]
      ]
    )
    # {:ok, ext} = Exile.Process.start_link(
    #   ["/bin/bash", command],
    #   stdin: :pipe,
    #   stderr: :consume,
    #   max_chunk_size: 1024
    # )
    #listen_for_output(ext)
    Logger.info("Started Python agent on ext: #{inspect(ext)} port:#{inspect(port_number)}")
    #Logger.info("Sleeping for 2000 ms...")
    #Process.sleep(2000)  # Allow the Python agent to start up
    #Logger.info("\n\nDone sleeping...")
    {:ok, ext}
  end








# ###
# These additions provide several important features:

# Health Monitoring:

# Regular health checks of both Elixir and Python processes
# Metrics tracking for requests and errors
# Automatic recovery from failures


# Supervision Strategy:

# Separate registries for agents and monitors
# Dynamic supervision for both components
# Graceful recovery from crashes


# Metrics and Logging:

# Detailed health metrics
# Error rate tracking
# Request/response monitoring
# Uptime tracking


# Recovery Mechanisms:

# Automatic process restart
# Configurable retry delays
# Graceful degradation



# To use this enhanced implementation:

# Start the supervisor:

# elixirCopyMyApp.Agent.Supervisor.start_link([])

# Start an agent:

# elixirCopyMyApp.Agent.Supervisor.start_agent("agent1")
# The system will automatically monitor the agent and its Python process, restarting them if necessary and maintaining metrics about their health.



  def handle_call(:ping, _from, %{channel: channel} = state) do
    case check_channel_health(channel) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp check_channel_health(channel) do
    # Simple health check request
    request = AI.PredictRequest.new(input: "ping")
    case channel |> AI.Service.Stub.predict(request, timeout: 5000) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_port_message({:exit_status, status}, state) do
    Logger.error("Python process exited with status: #{status}")
    {:stop, {:python_crash, status}, state}
  end

  defp handle_port_message(msg, state) do
    Logger.debug("Received port message: #{inspect(msg)}")
    {:noreply, state}
  end






  # defp listen_for_output(port) do
  #   # Continuously listen for data or other messages from the port
  #   receive do
  #     {^port, {:data, data}} ->
  #       Logger.info("Port Output: #{data}")
  #       listen_for_output(port)
  #     {^port, {_, data}} ->
  #       Logger.info("unexpected Port Output: #{data}")
  #       listen_for_output(port)

  #     {^port, :closed} ->
  #       IO.puts("Port closed")
  #       {:noreply, nil}
  #   end
  # end
end
