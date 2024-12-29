defmodule Axon.Agent.Server do
  @moduledoc """
  Agent.Server is the GenServer responsible for managing the state of a
  single agent. It handles the communication with the agent and keeps
  track of the agent's configuration, state, and chat history.
  """
  use GenServer
  require Logger

  alias AxonCore.AxonBridge.Client
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
        {:ok, ext}
      _ ->
        {:stop, :python_agent_start_failed}
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, ext) do
    case Client.process_data(message) do
      {:ok, response} ->
        {:reply, {:ok, response.result}, ext}
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

    python_cmd = AxonCore.PythonEnvManager.python_path()
    working_dir = Path.absname("apps/axon_python/src")


    env_vars = PythonEnvManager.env_vars()
    {_, _} = List.first(env_vars) ##TODO: cleanup



    ext = Port.open(
      {:spawn_executable, python_cmd},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: [Path.join(working_dir, "agent_server.py")],
        env: %{"PYTHONPATH" => working_dir}
      ]
    )

    Logger.info("Started Python agent on ext: #{inspect(ext)} port:#{inspect(port_number)}")
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



  def handle_call({:send_message, message}, _from, ext) do
    case Client.process_data(message) do
      {:ok, response} ->
        {:reply, {:ok, response.result}, ext}
      {:error, reason} ->
        Logger.error("Failed to send message to agent: #{inspect(reason)}")
        {:reply, {:error, reason}, ext}
    end
  end

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



################################ LATEST for gRPC

# defmodule MyApp.Agent.Server do
#   use GenServer
#   require Logger

#   def start_link(opts) do
#     GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:name]))
#   end

#   def init(opts) do
#     python_path = Path.join(File.cwd!(), "python")
#     port = start_python_process(python_path)

#     # Allow time for Python gRPC server to start
#     Process.sleep(1000)

#     # Connect to the Python gRPC server
#     {:ok, channel} = GRPC.Stub.connect("localhost:50051")

#     {:ok, %{port: port, channel: channel, name: opts[:name]}}
#   end

#   def handle_call({:predict, input}, _from, %{channel: channel} = state) do
#     # Unary call example
#     request = AI.PredictRequest.new(input: input)
#     {:ok, response} = channel |> AI.Service.Stub.predict(request)
#     {:reply, response.output, state}
#   end

#   def handle_call({:stream_predict, inputs}, _from, %{channel: channel} = state) do
#     # Streaming call example
#     stream = channel |> AI.Service.Stub.stream_predict([])

#     # Send requests
#     Enum.each(inputs, fn input ->
#       request = AI.PredictRequest.new(input: input)
#       GRPC.Stub.send_request(stream, request)
#     end)
#     GRPC.Stub.end_stream(stream)

#     # Collect responses
#     responses =
#       stream
#       |> Enum.map(& &1.output)
#       |> Enum.to_list()

#     {:reply, responses, state}
#   end

#   def terminate(_reason, %{port: port} = state) do
#     Port.close(port)
#     GRPC.Stub.disconnect(state.channel)
#   end

#   # Private functions

#   defp start_python_process(python_path) do
#     Port.open(
#       {:spawn_executable, "/usr/bin/python3"},
#       [
#         :binary,
#         :exit_status,
#         :hide,
#         args: [Path.join(python_path, "foo.py")],
#         cd: python_path,
#         env: [{"PYTHONPATH", python_path}]
#       ]
#     )
#   end

#   defp via_tuple(name) do
#     {:via, Registry, {MyApp.AgentRegistry, name}}
#   end
# end




# # proto/ai.proto
# syntax = "proto3";

# package ai;

# message PredictRequest {
#   string input = 1;
#   map<string, string> parameters = 2;
# }

# message PredictResponse {
#   string output = 1;
#   float confidence = 2;
# }

# service AIService {
#   rpc Predict(PredictRequest) returns (PredictResponse);
#   rpc StreamPredict(stream PredictRequest) returns (stream PredictResponse);
# }

# ```

# To use this implementation:

# 1. Set up your application structure:
# ```
# ├── lib/
# │   └── my_app/
# │       ├── application.ex
# │       └── agent/
# │           └── server.ex
# ├── python/
# │   ├── foo.py
# │   └── ai_pb2/
# │       ├── ai_pb2.py
# │       └── ai_pb2_grpc.py
# └── proto/
#     └── ai.proto
# ```

# 2. Add dependencies in mix.exs:
# ```elixir
# defp deps do
#   [
#     {:grpc, "~> 0.9"},
#     {:protobuf, "~> 0.11"}
#   ]
# end
# ```

# 3. Start the supervisor in your application.ex:
# ```elixir
# defmodule MyApp.Application do
#   use Application

#   def start(_type, _args) do
#     children = [
#       {Registry, keys: :unique, name: MyApp.AgentRegistry},
#       {DynamicSupervisor, name: MyApp.AgentSupervisor}
#     ]

#     opts = [strategy: :one_for_one, name: MyApp.Supervisor]
#     Supervisor.start_link(children, opts)
#   end
# end
# ```

# 4. Generate the Elixir protobuf code:
# ```bash
# protoc --elixir_out=plugins=grpc:./lib ai.proto
# ```

# Key features of this implementation:

# 1. **Process Management**:
#    - Uses Port for Python process management
#    - Proper cleanup in terminate callback
#    - Registry for named processes

# 2. **Communication**:
#    - gRPC for structured communication
#    - Both unary and streaming endpoints
#    - Type safety with Pydantic and Protobuf

# 3. **Python Side**:
#    - Async implementation with asyncio
#    - Type validation with Pydantic
#    - Proper gRPC server setup

# 4. **Error Handling**:
#    - Port monitors Python process
#    - gRPC error status codes
#    - Proper cleanup on termination

# Let me know if you'd like me to explain any part in more detail!
