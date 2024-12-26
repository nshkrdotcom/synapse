import Poison
defmodule AxonCore.AgentProcess do
  use GenServer
  require Logger

  alias AxonCore.{HTTPClient, JSONCodec, SchemaUtils, ToolUtils}
  alias AxonCore.Types, as: T

  @default_timeout 60_000
  @poll_interval 500 # Interval for polling for streamed data, in milliseconds

  @doc """
  Starts an agent process.

  ## Parameters

    - `name`: The name of the agent.
    - `python_module`: The module where the Python agent is defined.
    - `model`: The LLM model to use.
    - `port`: The port number for the agent's HTTP server.
    - `extra_env`: Extra environment variables.
  """
  def start_link(
        name: name,
        python_module: python_module,
        model: model,
        port: port,
        extra_env: extra_env \\ []
      ) do
    GenServer.start_link(__MODULE__, %{python_module: python_module, model: model, port: port, name: name},
      name: name
    )
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

  def get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, reuseaddr: true, active: false])
    {_, port} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
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
    GenServer.call(agent_name, {:send_message, message}, @default_timeout)
  end

  @doc """
  Initializes the agent process.

  Starts the Python agent process using `Port.open/2`.
  """
  # @impl true
  # def init(state) do
  #   # Start the Python agent process using Ports
  #   # Pass configuration as environment variables or command-line arguments
  #   port =
  #     Port.open(
  #       {:spawn_executable, "./python_agent_runner.sh"},
  #       [
  #         {:args, [state.python_module, Integer.to_string(state.port), state.model |> inspect()]}
  #         # this is necessary so that poetry can be found
  #         | Enum.into(state.extra_env, [{:cd, "./python_agents"}])
  #       ]
  #     )

  #   {:ok, %{state | port: port}}
  # end
  @impl true
  def init(state) do
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

    python_process =
      Port.open(
        {:spawn_executable, spawn_port},
        [
          {:args,
           [
             state.python_module || raise("--python_module is required"),
             Integer.to_string(port),
             state.model || raise("--model is required")
           ]},
          {:cd, "apps/axon_python/src"},
          {:env, ["PYTHONPATH=./", "AXON_PYTHON_AGENT_MODEL=#{state.model}" | state.extra_env]},
          :binary,
          :use_stdio,
          :stderr_to_stdout,
          :hide
        ]
      )

    # Store the port and python process in the state
    {:ok, %{state | port: port, python_process: python_process}}
  end




  # @impl true
  # def init(state) do
  #   # Start the Python agent process using Ports
  #   # Pass configuration as environment variables or command-line arguments
  #   port =
  #     Port.open(
  #       {:spawn_executable, "./python_agent_runner.sh"},
  #       [
  #         {:args, [state.python_module, Integer.to_string(state.port), state.model]},
  #         {:cd, "./python_agents"},
  #         {:env, ["OPENAI_API_KEY=#{System.get_env("OPENAI_API_KEY")}"]},
  #         :binary,
  #         :use_stdio,
  #         :exit_status
  #       ]
  #     )

  #   {:ok, %{state | port: port}}
  # end

  # def send_message(agent_name, message) do
  #   GenServer.call(agent_name, {:send_message, message}, @default_timeout)
  # end




  # # ... (other code)

  # @impl true
  # def init(state) do
  #   # Start the Python agent process using Ports
  #   # Pass configuration as environment variables or command-line arguments
  #   port =
  #     Port.open(
  #       {:spawn_executable, "./python_agent_runner.sh"},
  #       [
  #         {:args, [state.python_module, Integer.to_string(state.port), state.model]},
  #         {:cd, "./python_agents"},
  #         {:env, ["OPENAI_API_KEY=#{System.get_env("OPENAI_API_KEY")}"]},
  #         :binary,
  #         :use_stdio,
  #         :exit_status
  #       ]
  #     )

  #   {:ok, %{state | port: port}}
  # end

  # # ... (other code, including handle_call for sending messages)

  # @impl true
  # def handle_call({:send_message, message}, _from, state) do
  #   # Send an HTTP request to the Python agent
  #   endpoint = "http://localhost:#{state.port}/run"
  #   headers = [{"Content-Type", "application/json"}]

  #   with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(message)) do
  #     # Process the response
  #     {:reply, {:ok, JSONCodec.decode(response.body)}, state}
  #   else
  #     {:error, reason} ->
  #       # Handle error, potentially restart the Python process using the supervisor
  #       {:reply, {:error, reason}, state}
  #   end
  # end
  # @impl true
  # def handle_call({:send_message, message}, from, state) do
  #   # Construct the full endpoint URL for the specific agent
  #   endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
  #   headers = [{"Content-Type", "application/json"}]

  #   # Encode the message to JSON
  #   encoded_message = JSONCodec.encode(message)

  #   # Log the outgoing message
  #   Logger.info("Sending message to agent #{state.name}: #{inspect(message)}")

  #   # Send an HTTP POST request to the Python agent
  #   with {:ok, response} <- HTTPClient.post(endpoint, headers, encoded_message) do
  #     # Process the response
  #     case process_response(response) do
  #       {:ok, result} ->
  #         # Log successful result and usage
  #         Logger.info("Agent #{state.name} returned: #{inspect(result)}")
  #         {:reply, {:ok, result}, state}

  #       {:error, reason} ->
  #         # Log the error
  #         Logger.error("Agent #{state.name} run failed: #{reason}")
  #         # Handle error (retry, restart, escalate, etc.)
  #         handle_error(state, reason, from)
  #     end
  #   else
  #     {:error, reason} ->
  #       Logger.error("HTTP request to agent #{state.name} failed: #{reason}")
  #       {:reply, {:error, reason}, state}
  #   end
  # end
  @impl true
  def handle_call({:send_message, message}, from, state) do
    # Send an HTTP request to the Python agent
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/run_sync"
    headers = [{"Content-Type", "application/json"}]

    # Encode the message to JSON and send the request
    with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(message)) do
      # Process the response based on status code
      case response do
        %{status_code: 200, body: body} ->
          # Attempt to decode the response body
          try do
            decoded_response = JSONCodec.decode(body)

            # Check for the expected keys in the decoded response
            case {Map.has_key?(decoded_response, "result"), Map.has_key?(decoded_response, "usage")} do
              {true, true} ->
                result = Map.get(decoded_response, "result")
                usage = Map.get(decoded_response, "usage")
                # Log successful result and usage
                Logger.info("Agent #{state.name} returned: #{inspect(result)}")
                Logger.info("Usage info: #{inspect(usage)}")
                {:reply, {:ok, result, usage}, state}

              _ ->
                # Handle the case where expected keys are missing
                Logger.error("Incomplete response data from agent #{state.name}")
                {:reply, {:error, :incomplete_response}, state}
            end
          rescue
            e in JSON.DecodeError ->
              # Handle JSON decoding error
              Logger.error("Failed to decode response from agent #{state.name}: #{inspect(e)}")
              {:reply, {:error, :decode_error}, state}
          end

        %{status_code: status_code, body: body} ->
          # Handle error responses
          Logger.error("Agent #{state.name} run failed with status #{status_code}: #{body}")
          {:reply, {:error, "Agent run failed with status #{status_code}"}, state}
      end
    else
      # Handle HTTP request errors
      {:error, reason} ->
        Logger.error("HTTP request to agent #{state.name} failed: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end


  # Example of how to call a tool from handle_call (or another handler)
  def handle_call({:run_sync, request}, from, state) do
    # ... (previous logic for preparing the request)

    # Assuming the model returns a tool call, you would extract the tool name and arguments
    # For example:
    # tool_call = extract_tool_call_from_response(response)

    # Instead of directly executing the tool, send a message to self() to run the tool
    # Generate a unique request ID to track the request-response cycle
    request_id = :erlang.unique_integer([:positive])

    send(self(), {:run_tool, tool_call.name, tool_call.args, request_id})

    # Tell the caller we have initiated the action and will send a response later
    {:noreply, Map.put(state, :requests, Map.put(state.requests, request_id, {:run_sync, from, request}))}

    # ... (rest of your handle_call logic)
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

  # ...

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






  def handle_call({:call_tool, tool_name, args}, from, state) do
    # Assuming tool definitions are stored in the state
    case state.tools[tool_name] do
      {:elixir, fun} ->
        # Call Elixir function directly
        case ToolUtils.call_elixir_tool(fun, args) do
          {:ok, result} ->
            {:reply, {:ok, result}, state}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:python, module: module, function: function} ->
        # Send a request to Python to call the function
        request_id = :erlang.unique_integer([:positive]) |> Integer.to_string()
        send(self(), {:call_python_tool, request_id, module, function, args})
        {:noreply, Map.put(state, :requests, Map.put(state.requests, request_id, {:tool_call, from, nil}))}

      nil ->
        {:reply, {:error, "Tool not found: #{tool_name}"}, state}
    end
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


  @impl true
  def handle_info({:http_response, request_id, status_code, headers, body}, state) do
    # Find the original request data based on the request_id
    case Map.fetch(state.requests, request_id) do
      {:ok, {original_call_type, original_from, original_request}} ->
        case original_call_type do
          :run_sync ->
            # Handle the response for a synchronous run
            case process_response(response) do
              {:ok, result, usage} ->
                # to do: do we need to process the messages? they're already handled by pydantic-ai
                # # If there are any messages, you might want to log them or process them
                # if messages && messages != [] do
                #   Logger.info("Messages from agent: #{inspect(messages)}")
                # end
                GenServer.reply(original_from, {:ok, result, usage})
                {:noreply, Map.delete(state, :requests)}

              {:error, reason} ->
                GenServer.reply(original_from, {:error, reason})
                {:noreply, Map.delete(state, :requests)}
            end

          :run_stream ->
            # Handle streamed responses
            case status_code do
              200 ->
                # Process the streamed chunk
                case JSONCodec.decode(body) do
                  {:ok, %{"status" => "chunk", "data" => chunk}} ->
                    # Send the chunk to the caller
                    send(original_from, {:stream_chunk, chunk})
                    # Schedule the next poll
                    Process.send_after(self(), {:poll_stream, request_id}, @poll_interval)
                    {:noreply, state}

                  {:ok, %{"status" => "complete"}} ->
                    # Stream has completed, send the final usage info if available
                    usage = Map.get(JSONCodec.decode(body), "usage")
                    GenServer.reply(original_from, {:ok, usage})
                    {:noreply, Map.delete(state, :requests)}

                  {:error, reason} ->
                    # Handle decoding error
                    GenServer.reply(original_from, {:error, reason})
                    {:noreply, Map.delete(state, :requests)}
                end

              _ ->
                # Handle other HTTP status codes (errors)
                {:reply, {:error, "Unexpected HTTP status: #{status_code}"}, Map.delete(state, :requests)}
            end

          :log ->
            # Handle log messages
            case JSONCodec.decode(body) do
              {:ok, log_entry} ->
                Logger.info("Agent #{state.name} (log): #{inspect(log_entry)}")
                {:noreply, state}

              {:error, reason} ->
                Logger.error("Error decoding log message from agent #{state.name}: #{reason}")
                {:noreply, state}
            end
        end

      :error ->
        Logger.error("Received HTTP response for unknown request ID: #{request_id}")
        {:noreply, state}
    end
  end

  # def handle_info({:poll_stream, request_id}, state) do
  #   # Poll the Python agent for more streamed data
  #   # ... (Implementation depends on how you design the streaming API in Python)
  #   # ... (e.g., send an HTTP GET request to a `/stream` endpoint with a request_id)

  #   case HTTPClient.get("http://localhost:#{state.port}/stream/#{request_id}") do
  #     {:ok, response} ->
  #       # Process the streamed chunk (similar to handle_info with :run_stream)
  #       {:noreply, state}

  #     {:error, reason} ->
  #       Logger.error("Error while polling for streamed data: #{reason}")
  #       {:noreply, state}
  #   end
  # end
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
  def handle_info({:run_tool, tool_name, tool_args, request_id}, state) do
    endpoint = "http://localhost:#{state.port}/agents/#{state.name}/tool_call"
    headers = [{"Content-Type", "application/json"}]
    body = %{
      "tool_name" => tool_name,
      "args" => tool_args
    } |> JSONCodec.encode!() # Ensure args are encoded as JSON

    case HTTPClient.post(endpoint, headers, body) do
      {:ok, %{status_code: 200, body: response_body}} ->
        # Send the tool result back to the agent process that initiated the tool call
        send(state.caller, {:tool_result, request_id, response_body})

      {:error, reason} ->
        # Handle the error, potentially log it or send an error message back to the agent
        Logger.error("Error calling tool #{tool_name} on agent #{state.name}: #{reason}")
        send(state.caller, {:tool_error, request_id, reason})
    end

    {:noreply, state}
  end


  def handle_info(_msg, state) do
    Logger.warn("Agent process received unexpected message: #{inspect(_msg)}")
    {:noreply, state}
  end



  def handle_info(_msg, state) do
    Logger.warn("Agent process received unexpected message: #{inspect(_msg)}")
    {:noreply, state}
  end





  # @impl true
  # def handle_call({:send_message, message}, _from, state) do
  #   # Send an HTTP request to the Python agent
  #   endpoint = "http://localhost:#{state.port}/run"
  #   headers = [{"Content-Type", "application/json"}]


  #   with {:ok, response} <- HTTPClient.post(endpoint, headers, JSONCodec.encode(request)) do
  #     case process_response(response) do
  #       {:ok, result} ->
  #         # Log successful result
  #         Logger.info("Agent #{state.name} returned: #{inspect(result)}")
  #         {:reply, {:ok, result}, state}
  #       {:error, reason} ->
  #         # Log the error
  #         Logger.error("Agent #{state.name} run failed: #{reason}")
  #         # Handle error (retry, restart, escalate, etc.)
  #         handle_error(state, reason, from)
  #     end
  #   else
  #     {:error, reason} ->
  #       Logger.error("HTTP request to agent #{state.name} failed: #{reason}")



  # ... (handle_info for receiving streamed data, errors, etc.)

  # defp process_response(response) do
  #   case response do
  #     %{status_code: 200, body: body} ->
  #       try do
  #         decoded_response = JSONCodec.decode(body)
  #         handle_success(decoded_response)
  #       rescue
  #         e in [JSON.DecodeError, KeyError] ->
  #           {:error, "Error decoding response: #{inspect(e)}"}
  #       end

  #     %{status_code: status_code, body: body} ->
  #       handle_error_response(status_code, body)
  #   end
  # end
  # defp process_response(response) do
  #   case response do
  #     %{status_code: 200, body: body} ->
  #       try do
  #         %{
  #           "result" => result,
  #           "usage" => usage,
  #           "messages" => messages
  #         } = JSONCodec.decode(body)

  #         handle_success(%{result: result, usage: usage, messages: messages})
  #       rescue
  #         e in [JSON.DecodeError, KeyError] ->
  #           {:error, "Error decoding response: #{inspect(e)}"}
  #       end

  #     %{status_code: status_code, body: body} ->
  #       handle_error_response(status_code, body)
  #   end
  # end
  defp process_response(response) do
    case response do
      %{status_code: 200, body: body} ->
        try do
          decoded_response = JSONCodec.decode(body)

          # Extract result and usage
          result = Map.get(decoded_response, "result")
          usage = Map.get(decoded_response, "usage")
          messages = Map.get(decoded_response, "messages")

          # Validate result against schema if necessary
          # if has_result_schema?(state) do
          #   validate_result(result, state.result_schema)
          # end

          {:ok, result, usage, messages}
        rescue
          e in [JSON.DecodeError, KeyError] ->
            {:error, "Error decoding response: #{inspect(e)}"}
        end

      %{status_code: status_code, body: body} ->
        handle_error_response(status_code, body)
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
