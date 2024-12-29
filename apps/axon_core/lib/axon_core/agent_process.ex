defmodule AxonCore.AgentProcess do
  use GenServer

  @default_model "default"
  @default_python_module "agents.example_agent"

  # Client API

  def start_link(opts) do
    Logger.info("#{inspect(opts)}")
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  def via_tuple(name) do
    {:via, Registry, {Axon.AgentRegistry, name}}
  end

  @impl true
  def init(opts) do
    state = %{
      name: Keyword.fetch!(opts, :name),
      model: Keyword.get(opts, :model, @default_model),
      python_module: Keyword.get(opts, :python_module, @default_python_module),
      python_script: opts[:python_script] || "foo.py",
      port: opts[:port],
      extra_env: Keyword.get(opts, :extra_env, []),
      channel: nil
      # ... other options ...
    }

    {:ok, port} = start_python_process(state)
    {:ok, channel} = setup_grpc_channel(state)
    {:ok, %{state | port: port, channel: channel}}
  end

  defp setup_grpc_channel(state) do
    Logger.info("Setting up gRPC channel for agent #{state.name}...")
    {:ok, channel} =
      :grpc.connect(
        "localhost:#{state.port}",
        channel_opts: [
          {:ssl, false}
        ]
      )
    Logger.info("gRPC channel setup complete for agent #{state.name}")
    {:ok, channel}
  end

  defp start_python_process(state) do
    python_command =
      if System.get_env("PYTHON_EXEC") != nil do
        System.get_env("PYTHON_EXEC")
      else
        "python3"
      end

    # Construct the command to start the Python process
    # Ensure the script uses the agent_id and port in its gRPC server setup
    port_number = state.port

    # Use a relative path for `cd`
    relative_path_to_python_src = "../../../apps/axon_python/src"

    port =
      Port.open(
        {:spawn_executable, System.find_executable("bash")},
        [
          {:args,
          [
            "-c",
            "cd #{relative_path_to_python_src}; source ../../.venv/bin/activate; #{python_command} -u axon_python/#{state.python_script} --port #{port_number} --agent_config '{\"model\": \"#{state.model}\", \"system_prompt\": \"You are a helpful assistant.\"}'"
          ]},
          {:cd, File.cwd!()},
          {:env,
            [
              "PYTHONPATH=./",
              "AXON_PYTHON_AGENT_MODEL=#{state.model}",
              "AXON_AGENT_ID=#{state.name}"
              | state.extra_env
            ]},
          :binary,
          :use_stdio,
          :stderr_to_stdout,
          :hide
        ]
      )

    Logger.info("Started Python agent #{state.name} on port #{port_number}")

    {:ok, port}
  end

  @impl true
  def handle_call({:run_sync, request}, _from, state) do
    # Convert Elixir request to gRPC request
    grpc_request =  %{
      agent_id: state.name,
      prompt: request.prompt,
      message_history: request.message_history || [],
      model_settings: request.model_settings || %{}
    }

    # Get the gRPC channel from the state
    channel = state.channel

    try do
      case Axon.AgentService.Stub.run_sync(channel, grpc_request) do
        {:ok, reply} ->
          response = %{
            result: Jason.decode!(reply.result), # Parse JSON string from Python
            usage: if reply.usage do
              %{
                request_tokens: reply.usage.request_tokens,
                response_tokens: reply.usage.response_tokens,
                total_tokens: reply.usage.total_tokens
              }
            end
          }
          {:reply, {:ok, response}, state}

        {:error, reason} ->
          Logger.error("gRPC call failed: #{inspect(reason)}")
          {:reply, {:error, :grpc_call_failed}, state}
      end
    rescue
      e ->
        Logger.error("Error in run_sync: #{inspect(e)}")
        {:reply, {:error, :internal_error}, state}
    end
  end

  # Add a convenience function for making requests
  def run_sync(agent_name, prompt, opts \\ []) do
    request = %{
      prompt: prompt,
      message_history: Keyword.get(opts, :message_history, []),
      model_settings: Keyword.get(opts, :model_settings, %{})
    }
    GenServer.call(via_tuple(agent_name), {:run_sync, request})
  end

  # Example of handling a streaming call (needs to be adapted for WebSockets)
  @impl true
  def handle_call({:run_stream, _request}, _from, _state) do
    # ... (similar to :run_sync, but use RunStream and handle chunks) ...
  end

  # Basic usage
  # AxonCore.AgentProcess.run_sync("agent1", "Hello, how are you?")

  # # With additional options
  # AxonCore.AgentProcess.run_sync("agent1", "Hello again",
  #   message_history: [%{role: "user", content: "previous message"}],
  #   model_settings: %{temperature: 0.7}
  # )

  # ... (handle_info for receiving data from the Port, error handling, etc.) ...
end
