defmodule AxonCore.AgentProcess do
  use GenServer
  require Logger

  alias AxonCore.{HTTPClient, JSONCodec, SchemaUtils, ToolUtils}
  alias AxonCore.Types, as: T

  @default_timeout 60_000
  @poll_interval 500 # Interval for polling for streamed data, in milliseconds

  def start_link(
        name: name,
        python_module: python_module,
        model: model,
        port: port,
        extra_env: extra_env \\ []
      ) do
    GenServer.start_link(__MODULE__, %{
      python_module: python_module,
      model: model,
      port: port,
      name: name,
      extra_env: extra_env,
      requests: %{},
      streams: %{}
    },
    name: name
    )
  end

  def pid(agent_name) when is_binary(agent_name) do
    case :pg.get_members(agent_name) do
      [] -> nil
      [pid | _] -> pid
    end
  end

  def get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, reuseaddr: true, active: false])
    {_, port} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  def send_message(agent_name, message) do
    GenServer.call(agent_name, {:send_message, message}, @default_timeout)
  end

  @impl true
  def init(state) do
    # Start the Python agent process
    port = get_free_port()
    python_command = System.get_env("PYTHON_EXEC", "python")
    {:ok, _} = Application.ensure_all_started(:os_mon)

    spawn_port = "#{python_command} -u -m axon_python.agent_wrapper"

    # Pass the python_module as an argument to the script
    port_args = [
      state.python_module || raise("python_module is required"),
      Integer.to_string(port),
      state.model || raise("model is required")
    ] ++ if state.extra_env do
      Enum.flat_map(state.extra_env, fn {k, v} -> ["--env", "#{k}=#{v}"] end)
    else
      []
    end

    # Use a relative path for `cd`
    relative_path_to_python_src = "../../../apps/axon_python/src"

    port = Port.open(
      {:spawn_executable, System.find_executable("bash")},
      [
        {:args, [
          "-c",
          "cd #{relative_path_to_python_src}; source ../../.venv/bin/activate; #{spawn_port} #{Enum.join(port_args, " ")}"
        ]},
        {:cd, File.cwd!()},
        {:env, ["PYTHONPATH=./", "AXON_PYTHON_AGENT_MODEL=#{state.model}" | state.extra_env]},
        :binary,
        :use_stdio,
        :stderr_to_stdout,
        :hide
      ]
    )

    {:ok, %{state | port: port}}
  end

  @impl true
  def init(state) do
    # Start the gRPC Server
    {:ok, _} = AxonCore.AgentGrpcServer.start(50051)

    # Start the Python agent process using Ports
    # Pass configuration as environment variables or command-line arguments
    port = get_free_port()

    python_command = System.get_env("PYTHON_EXEC", "python")

    {:ok, _} = Application.ensure_all_started(:os_mon)
    spawn_port = "#{python_command} -u -m axon_python.agent_wrapper"


    # Pass the python_module as an argument to the script
    port_args =
      [
        state.python_module || raise("python_module is required"),
        Integer.to_string(port),
        state.model || raise("model is required")
      ] ++
        if state.extra_env do
          Enum.flat_map(state.extra_env, fn {k, v} -> ["--env", "#{k}=#{v}"] end)
        else
          []
        end

    # Use a relative path for `cd`
    relative_path_to_python_src = "../../../apps/axon_python/src"

    port =
      Port.open(
        {:spawn_executable, System.find_executable("bash")},
        [
          {:args,
           [
             "-c",
             "cd #{relative_path_to_python_src}; source ../../.venv/bin/activate; #{spawn_port} #{Enum.join(port_args, " ")}"
           ]},
          {:cd, File.cwd!()},
          {:env, ["PYTHONPATH=./", "AXON_PYTHON_AGENT_MODEL=#{state.model}" | state.extra_env]},
          :binary,
          :use_stdio,
          :stderr_to_stdout,
          :hide
        ]
      )

    result_schema =
      case opts[:result_type] do
        nil ->
          nil

        result_type ->
          SchemaUtils.elixir_to_json_schema(result_type)
      end

    initial_state = %{
      state
      | port: port,
        python_process: python_process,
        result_schema: result_schema
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:send_message, message}, from, state) do
    # Send an HTTP request to the Python agent
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    # Encode the message to JSON and send the request
    with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(message)) do
      # Process the response based on status code
      case process_response(response) do
        {:ok, result, usage} ->
          # Log successful result and usage
          Logger.info("Agent #{state.name} returned: #{inspect(result)}")
          Logger.info("Usage info: #{inspect(usage)}")
          {:reply, {:ok, result, usage}, state}

        {:error, reason} ->
          # Log the error
          Logger.error("Agent #{state.name} run failed: #{reason}")
          # Handle error (retry, restart, escalate, etc.)
          handle_error(state, reason, from)
      end
    else
      {:error, reason} ->
        Logger.error("HTTP request to agent #{state.name} failed: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:call_tool, tool_name, args}, from, state) do
    # Assuming tool definitions are stored in the state under the :tools key
    case Map.fetch(state.tools, tool_name) do
      {:ok, tool_def} ->
        # Serialize the arguments to JSON
        with {:ok, json_args} <- ToolUtils.serialize_tool_args(tool_def, args) do
          # Construct the request to be sent to the Python agent
          endpoint = "http://localhost:#{state.port}/agents/#{state.name}/tool_call"
          headers = [{"Content-Type", "application/json"}]
          body = %{
            "tool_name" => tool_name,
            "args" => json_args
          }
          |> JSONCodec.encode!()

          # Send an HTTP POST request to call the tool
          with {:ok, response} <- HTTPClient.post(endpoint, headers, body) do
            # Process the tool call response
            case process_tool_response(response) do
              {:ok, result} ->
                # Reply to the caller with the tool result
                GenServer.reply(from, {:ok, result})
                {:noreply, state}

              {:error, reason} ->
                # Handle the error, potentially log it
                Logger.error("Tool call to #{tool_name} failed: #{reason}")
                GenServer.reply(from, {:error, reason})
                {:noreply, state}
            end
          else
            {:error, reason} ->
              # Handle HTTP request errors
              Logger.error("HTTP request to agent #{state.name} for tool #{tool_name} failed: #{reason}")
              GenServer.reply(from, {:error, reason})
              {:noreply, state}
          end
        else
          {:error, reason} ->
            # Handle errors during argument serialization
            Logger.error("Failed to serialize arguments for tool #{tool_name}: #{reason}")
            GenServer.reply(from, {:error, reason})
            {:noreply, state}
        end

      :error ->
        # Handle the case where the tool is not found
        Logger.error("Tool not found: #{tool_name}")
        GenServer.reply(from, {:error, "Tool not found: #{tool_name}"})
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:run_sync, request}, from, state) do
    # Generate a unique request ID for this streaming request
    request_id = :erlang.unique_integer([:positive]) |> Integer.to_string()

    # Send an HTTP POST request to start the streaming run
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    # For demonstration, let's assume the agent decides to call a tool here
    # In a real scenario, this would be based on the LLM's response
    tool_call_needed = true # Simulate a condition where a tool call is needed

    if tool_call_needed do
      # Simulate tool call details (replace with actual logic to determine tool name and arguments)
      tool_name = "some_tool" # Replace with the actual tool name from the agent's response
      tool_args = %{"arg1" => "value1", "arg2" => 2} # Replace with actual arguments

      # Store the caller's `from` tag along with the request ID to handle the tool call result later
      new_state = Map.put(state, :requests, Map.put(state.requests, request_id, {:tool_call, from, request}))

      # Send a message to self to call the tool
      send(self(), {:call_tool, tool_name, tool_args, request_id})

      # Indicate to the caller that the request is being processed
      {:noreply, new_state}
    else
      # Proceed with the existing logic if no tool call is needed
      # Store the caller's `from` tag along with the request ID to handle the response later
      new_state = Map.put(state, :requests, Map.put(state.requests, request_id, {:run_sync, from, request}))

      # Send the HTTP request asynchronously
      send_request_async(endpoint, headers, JSONCodec.encode!(request), request_id)

      {:noreply, new_state}
    end
  end

  defp send_request_async(endpoint, headers, body, request_id) do
    Task.start_link(fn ->
      with {:ok, response} <- HTTPClient.post(endpoint, headers, body) do
        # Send the response back to the AgentProcess using the request_id
        send(self(), {:http_response, request_id, response.status_code, response.headers, response.body})
      else
        {:error, reason} ->
          # Handle HTTP request errors
          Logger.error("HTTP request failed: #{reason}")
          send(self(), {:http_error, request_id, reason})
      end
    end)
  end

  def handle_info({:http_error, request_id, reason}, state) do
    # Log the error
    Logger.error("HTTP request failed for request_id #{request_id}: #{reason}")

    # Find the original caller and inform about the error
    case Map.fetch(state.requests, request_id) do
      {:ok, {from, _original_request}} ->
        GenServer.reply(from, {:error, :http_request_failed})

      :error ->
        Logger.error("Could not find caller for request_id: #{request_id}")
    end

    # Remove the request from the state
    {:noreply, %{state | requests: Map.delete(state.requests, request_id)}}
  end

  @doc """
  Initiates a streaming run of the agent.

  ## Parameters

    - `agent_name`: The name of the agent.
    - `prompt`: The initial prompt for the agent.
    - `message_history`: An optional list of previous messages.
    - `model_settings`: Optional model settings.
    - `usage_limits`: Optional usage limits.

  ## Returns

  `{:ok, stream_id}` to indicate that the streaming request has been accepted.
  The client should then listen for `:stream_chunk` messages.
  """
  def run_stream(agent_name, prompt, message_history \\ [], model_settings \\ %{}, usage_limits \\ %{}) do
    GenServer.call(agent_name, {:run_stream, prompt, message_history, model_settings, usage_limits}, @default_timeout)
  end

  def handle_call({:run_stream, request}, from, state) do
    # Create a unique request ID for this stream
    request_id = :erlang.unique_integer([:positive]) |> Integer.to_string()

    # Store the caller's PID and the request ID for sending stream chunks later
    new_state = Map.put(state, :streams, Map.put(state.streams, request_id, from))

    # Start a task to handle the stream
    Task.start_link(fn ->
      handle_streaming_request(state.grpc_channel, request, request_id, self())
    end)

    # Acknowledge the start of the streaming
    {:reply, {:ok, request_id}, new_state}

    #end
  end

  defp handle_streaming_request(grpc_channel, request, request_id, agent_pid) do
    try do
      stream = Axon.AgentService.Stub.run_stream(grpc_channel, request)

      # Iterate over the stream and send chunks to the original caller
      Stream.each(stream, fn chunk ->
        send(agent_pid, {:stream_chunk, request_id, chunk})
      end)

      # Handle stream completion
      receive do
        {:stream_complete, request_id, usage} ->
          send(agent_pid, {:stream_complete, request_id, usage})

        {:stream_error, request_id, reason} ->
          send(agent_pid, {:stream_error, request_id, reason})
      after
        @default_timeout ->
          Logger.error("Stream timeout for request_id: #{request_id}")
          send(agent_pid, {:stream_error, request_id, "Timeout"})
      end
    catch
      # Handle exceptions during streaming
      e ->
        Logger.error("Error during streaming for request_id: #{request_id}: #{inspect(e)}")
        send(agent_pid, {:stream_error, request_id, e})
    end
  end

  @impl true
  def handle_call({:call_tool, tool_name, args}, from, state) do
    # Construct the request to be sent to the Python agent
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/tool_call"
    headers = [{"Content-Type", "application/json"}]
    body = %{
      "tool_name" => tool_name,
      "args" => args
    }
    |> JSONCodec.encode!()

    # Send an HTTP POST request to call the tool
    with {:ok, response} <- HTTPClient.post(endpoint, headers, body) do
      # Process the tool call response
      case process_tool_response(response) do
        {:ok, result} ->
          # Reply to the caller with the tool result
          GenServer.reply(from, {:ok, result})
          {:noreply, state}

        {:error, reason} ->
          # Handle the error, potentially log it
          Logger.error("Tool call to #{tool_name} failed: #{reason}")
          GenServer.reply(from, {:error, reason})
          {:noreply, state}
      end
    else
      {:error, reason} ->
        # Handle HTTP request errors
        Logger.error("HTTP request to agent #{state.name} for tool #{tool_name} failed: #{reason}")
        GenServer.reply(from, {:error, reason})
        {:noreply, state}
    end
  end

  defp process_tool_response(response) do
    case response do
      %{status_code: 200, body: body} ->
        try do
          decoded_response = JSONCodec.decode(body)
          {:ok, Map.get(decoded_response, "result")}
        rescue
          e in [JSON.DecodeError, KeyError] ->
            {:error, "Error decoding tool response: #{inspect(e)}"}
        end

      %{status_code: status_code} ->
        {:error, "Tool call failed with status code: #{status_code}"}
    end
  end

  @impl true
  def handle_info({:stream_chunk, request_id, chunk}, state) do
    case Map.fetch(state.streams, request_id) do
      {:ok, from} ->
        # Relay the chunk to the original caller
        send(from, {:stream_chunk, chunk})
        {:noreply, state}

      :error ->
        # Handle the case where the stream has been closed or the ID is invalid
        Logger.warn("Received stream chunk for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  def handle_info({:stream_complete, request_id, usage}, state) do
    case Map.fetch(state.streams, request_id) do
      {:ok, from} ->
        send(from, {:stream_complete, usage})
        {:noreply, Map.update!(state, :streams, &Map.delete(&1, request_id))}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:stream_error, request_id, reason}, state) do
    case Map.fetch(state.streams, request_id) do
      {:ok, from} ->
        send(from, {:stream_error, reason})
        {:noreply, Map.update!(state, :streams, &Map.delete(&1, request_id))}

      :error ->
        {:noreply, state}
    end
  end


  def handle_info({:grpc_stream_response, request_id, chunk}, state) do
    case Map.fetch(state.streams, request_id) do
      {:ok, from} ->
        # Relay the chunk to the original caller
        send(from, {:stream_chunk, chunk})
        {:noreply, state}

      :error ->
        # Handle the case where the stream has been closed or the ID is invalid
        Logger.warn("Received stream chunk for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:run_stream, prompt, message_history, model_settings, usage_limits}, from, state) do
    # Generate a unique request ID for this streaming request
    request_id = :erlang.unique_integer([:positive]) |> Integer.to_string()

    # Construct the request to be sent to the Python agent
    request = %{
      "prompt" => prompt,
      "message_history" => message_history,
      "model_settings" => model_settings,
      "usage_limits" => usage_limits
    }

    # Send an HTTP POST request to start the streaming run
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_stream"
    headers = [{"Content-Type", "application/json"}]
    send(self(), {:start_streaming, request_id, from})

    with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(request)) do
      # Process the response
      {:reply, {:ok, request_id},
       Map.put(
         state,
         :requests,
         Map.put(state.requests, request_id, {:run_stream, from, request, response})
       )}
    else
      {:error, reason} ->
        # Handle error, potentially restart the Python process using the supervisor
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:start_streaming, request_id, from}, state) do
    # Start polling for streamed data
    Process.send_after(self(), {:poll_stream, request_id}, @poll_interval)
    # Update state to include the 'from' tag for sending responses back to caller
    {:noreply, Map.put(state, :requests, Map.put(state.requests, request_id, {:run_stream, from, nil, nil}))}
  end

  def handle_info({:call_python_tool, request_id, module, function, args}, state) do
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/tool_call"
    headers = [{"Content-Type", "application/json"}]
    body = %{
      "module" => module,
      "function" => function,
      "args" => args
    } |> JSONCodec.encode!()

    with {:ok, response} <- HTTPClient.post(endpoint, headers, body) do
      case process_tool_response(response) do
        {:ok, result} ->
          # Find the original caller based on request_id and reply
          case Map.fetch(state.requests, request_id) do
            {:ok, {:tool_call, original_from, _}} ->
              send(original_from, {:tool_result, request_id, result})
            _ ->
              Logger.error("Could not find caller for request_id: #{request_id}")
          end
          {:noreply, Map.delete(state, :requests)}

        {:error, reason} ->
          # Handle error, potentially retry or escalate
          Logger.error("Tool call error: #{reason}")
          {:noreply, state}
      end
    else
      {:error, reason} ->
        Logger.error("HTTP request to agent #{state.name} failed: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_info({:tool_result, request_id, result}, state) do
    # Find the original caller based on request_id
    case Map.fetch(state.requests, request_id) do
      {:ok, {:run_sync, original_from, _}} ->
        # In a real scenario, you would now resume the agent's execution
        # using the result of the tool call.

        # For this example, we simply send the result back to the original caller.
        send(original_from, {:ok, result})

        # Remove the request from the state
        {:noreply, Map.delete(state, :requests, request_id)}

      _ ->
        Logger.error("Received tool result for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  # Handle the response from the Python agent
  @impl true
  def handle_info({:http_response, request_id, status_code, headers, body}, state) do
    case Map.fetch(state.requests, request_id) do
      {:ok, {call_type, from, original_request}} ->
        case call_type do
          :run_sync ->
            handle_run_sync_response(status_code, body, from, state, request_id)

          :run_stream ->
            handle_run_stream_response(status_code, body, from, state, request_id)

          :log ->
            handle_log_response(body, state)
        end

      :error ->
        Logger.error("Received HTTP response for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  defp handle_run_sync_response(200, body, from, state, request_id) do
    try do
      %{
        "result" => result,
        "usage" => usage,
        "messages" => messages
      } = JSONCodec.decode!(body)

      # Log successful result and usage information
      Logger.info("Agent #{state.name} returned: #{inspect(result)}")
      Logger.info("Usage info: #{inspect(usage)}")
      log_messages(messages)

      GenServer.reply(from, {:ok, result, usage})
      {:noreply, Map.delete(state, :requests, request_id)}
    rescue
      e in [JSON.DecodeError, KeyError] ->
        Logger.error("Error decoding response: #{inspect(e)}")
        GenServer.reply(from, {:error, :decode_error})
        {:noreply, Map.delete(state, :requests, request_id)}
    end
  end

  defp handle_run_sync_response(status_code, body, from, state, request_id) do
    Logger.error("Agent #{state.name} run failed with status #{status_code}: #{body}")
    GenServer.reply(from, {:error, "Agent run failed with status #{status_code}"})
    {:noreply, Map.delete(state, :requests, request_id)}
  end

  defp handle_run_stream_response(200, body, from, state, request_id) do
    # Process the streamed chunk
    case JSONCodec.decode!(body) do
      %{"status" => "chunk", "data" => chunk} ->
        # Send the chunk to the caller
        send(from, {:stream_chunk, chunk})
        # Schedule the next poll
        Process.send_after(self(), {:poll_stream, request_id}, @poll_interval)
        {:noreply, state}

      %{"status" => "complete"} ->
        # Stream has completed, send the final usage info if available
        usage = Map.get(JSONCodec.decode!(body), "usage")
        GenServer.reply(from, {:ok, usage})
        {:noreply, Map.delete(state, :requests)}

      {:error, reason} ->
        # Handle decoding error
        GenServer.reply(from, {:error, reason})
        {:noreply, Map.delete(state, :requests)}
    end
  end

  defp handle_run_stream_response(status_code, _body, from, state, request_id) do
    # Handle other HTTP status codes (errors)
    GenServer.reply(from, {:error, "Unexpected HTTP status: #{status_code}"})
    {:noreply, Map.delete(state, :requests, request_id)}
  end

  defp handle_log_response(body, state) do
    # Handle log messages
    case JSONCodec.decode!(body) do
      {:ok, log_entry} ->
        Logger.info("Agent #{state.name} (log): #{inspect(log_entry)}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Error decoding log message from agent #{state.name}: #{reason}")
        {:noreply, state}
    end
  end

  defp log_messages(messages) when is_list(messages) do
    Enum.each(messages, &log_message/1)
  end

  defp log_messages(_), do: :ok

  defp log_message(msg) do
    Logger.info("Agent Message: #{inspect(msg)}")
  end

  def handle_info({:poll_stream, request_id}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        # Request is not in the state anymore, it might have been completed or errored out
        {:noreply, state}

      {_call_type, from, _request, _response} ->
        # Poll the Python agent for more streamed data
        endpoint = "http://localhost:#{state.port}/stream/#{request_id}"

        case HTTPClient.get(endpoint) do
          {:ok, response} ->
            # Process the streamed chunk
            case process_streaming_response(response, from) do
              :continue ->
                # Schedule the next poll if the stream is still active
                Process.send_after(self(), {:poll_stream, request_id}, @poll_interval)
                {:noreply, state}

              :completed ->
                # Remove the request from the state as the stream is completed
                {:noreply, Map.delete(state.requests, request_id)}
            end

          {:error, reason} ->
            Logger.error("Error while polling for streamed data for agent #{state.name}: #{reason}")
            # Notify the original caller about the error
            send(from, {:error, "Error during streaming: #{reason}"})
            {:noreply, Map.delete(state.requests, request_id)}
        end
    end
  end

  @impl true
  def handle_info({:run_tool, tool_name, args, request_id}, state) do
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/tool_call"
    headers = [{"Content-Type", "application/json"}]
    body = %{
      "tool_name" => tool_name,
      "args" => args
    }
    |> JSONCodec.encode!()

    with {:ok, response} <- HTTPClient.post(endpoint, headers, body) do
      case process_tool_response(response) do
        {:ok, result} ->
          # Find the original caller based on request_id and reply
          case Map.fetch(state.requests, request_id) do
            {:ok, {:tool_call, original_from, _}} ->
              send(original_from, {:tool_result, request_id, result})
            _ ->
              Logger.error("Could not find caller for request_id: #{request_id}")
          end
          {:noreply, Map.delete(state, :requests)}

        {:error, reason} ->
          # Handle error, potentially retry or escalate
          Logger.error("Tool call error: #{reason}")
          {:noreply, state}
      end
    else
      {:error, reason} ->
        Logger.error("HTTP request to agent #{state.name} failed: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_info({:tool_error, request_id, reason}, state) do
    # ... similar to :tool_result, but handle the error
    case Map.fetch(state.requests, request_id) do
      {:ok, {:run_sync, original_from, _}} ->
        # In a real scenario, you would now resume the agent's execution
        # using the result of the tool call.

        # For this example, we simply send the result back to the original caller.
        send(original_from, {:ok, result})

        # Remove the request from the state
        {:noreply, Map.delete(state, :requests, request_id)}

      _ ->
        Logger.error("Received tool result for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    Logger.warn("Agent process received unexpected message: #{inspect(_msg)}")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    Logger.warn("Agent process received unexpected message: #{inspect(_msg)}")
    {:noreply, state}
  end

  defp process_response(response) do
    case response do
      %{status_code: 200, body: body} ->
        try do
          decoded_response = JSONCodec.decode(body)

          # Extract result and usage
          result = Map.get(decoded_response, "result")
          usage = Map.get(decoded_response, "usage")
          messages = Map.get(decoded_response, "messages") ## ??

          # Validate result if schema is available
          if state.result_schema do
            case SchemaUtils.validate(state.result_schema, result) do
              :ok ->
                {:ok,
                 result,
                 usage,
                 messages}

              {:error, reason} ->
                Logger.error("Result validation failed: #{inspect(reason)}")
                {:error, :result_validation_failed, reason}
            end
          else
            {:ok, result, usage, messages}
          rescue
            e in [JSON.DecodeError, KeyError] ->
              {:error, "Error decoding response: #{inspect(e)}"}
          end
        end
      %{status_code: status_code, body: body} ->
        handle_error_response(status_code, body)

    end
  end

  defp process_tool_response(response) do
    case response do
      %{status_code: 200, body: body} ->
        try do
          decoded_response = JSONCodec.decode(body)
          {:ok, decoded_response["result"]}
        rescue
          e in [JSON.DecodeError, KeyError] ->
            {:error, "Error decoding tool response: #{inspect(e)}"}
        end
      %{status_code: status_code, body: body} ->
        {:error, "Tool call HTTP error: #{status_code}"}
    end
  end

  defp handle_success(%{result: result, usage: usage, messages: messages}) do
    # Log successful result and usage
    Logger.info("Agent run completed successfully. Result: #{inspect(result)}, Usage: #{inspect(usage)}")

    # If there are any messages, you might want to log them or process them
    if messages && messages != [] do
      Logger.info("Messages from agent: #{inspect(messages)}")
    end

    # Return the result and usage
    {:ok, %{result: result, usage: usage}}
  end


  defp handle_success(decoded_response) do
    # Assuming the response contains a "result" key for successful runs
    case Map.fetch(decoded_response, "result") do
      {:ok, result} -> {:ok, result}
      :error -> {:error, "Missing result in successful response"}
    end
  end


  defp handle_error_response(status_code, body) do
    try do
      # Attempt to decode the body as JSON, expecting error details
      %{
        "status" => "error",
        "error_type" => error_type,
        "message" => message,
        "details" => details
      } = JSONCodec.decode(body)

      # Log the error with details
      Logger.error("Python agent error: #{error_type} - #{message}", details: details)

      # Here you can pattern match on `error_type` to handle specific errors
      case error_type do
        "ValidationError" ->
          # Handle validation errors, potentially retrying the operation
          {:error, :validation_error, details}

        # "ModelRetry" ->
        "UnexpectedModelBehavior" ->
          # Handle model retry request
          {:error, :model_retry, message}

        _ ->
          # Handle other errors as needed
          {:error, :unknown_error, message}
      end
    rescue
      # If JSON decoding or key lookup fails, log the raw body
      e in [JSON.DecodeError, KeyError] ->
        Logger.error("Error decoding error response: #{inspect(e)}")
        {:error, :decode_error, body}
    else
      # If status code is not 200, treat as a general error
      {:error, "HTTP error: #{status_code}", body}
    end
  end


  defp handle_error(state, reason, from) do
    # Implement your error handling logic here
    # For example, retry the operation, restart the agent, or escalate the error
    case reason do
      :validation_error ->
        # Potentially retry with a modified request
        {:reply, {:error, reason}, state}

      :model_retry ->
        # Handle model retry request
        {:reply, {:error, reason}, state}

      _ ->
        # Escalate the error or handle it according to your application's needs
        {:reply, {:error, reason}, state}
    end
  end
end
