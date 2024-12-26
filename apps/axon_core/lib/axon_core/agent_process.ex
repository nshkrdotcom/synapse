defmodule AxonCore.AgentProcess do
  use GenServer

  alias AxonCore.{HTTPClient, JSONCodec, SchemaUtils, ToolUtils}
  alias AxonCore.Types, as: T

  @default_timeout 60_000

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


  def get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, reuseaddr: true, active: false])
    {_, port} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end


  @doc """
  Initializes the agent process.

  Starts the Python agent process using `Port.open/2`.
  """
  @impl true
  def init(state) do
    # Start the Python agent process using Ports
    # Pass configuration as environment variables or command-line arguments
    port =
      Port.open(
        {:spawn_executable, "./python_agent_runner.sh"},
        [
          {:args, [state.python_module, Integer.to_string(state.port), state.model |> inspect()]}
          # this is necessary so that poetry can be found
          | Enum.into(state.extra_env, [{:cd, "./python_agents"}])
        ]
      )

    {:ok, %{state | port: port}}
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

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    # Send an HTTP request to the Python agent
    endpoint = "http://localhost:#{state.port}/run"
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

  defp process_response(response) do
    case response do
      %{status_code: 200, body: body} ->
        try do
          decoded_response = JSONCodec.decode(body)
          handle_success(decoded_response)
        rescue
          e in [JSON.DecodeError, KeyError] ->
            {:error, "Error decoding response: #{inspect(e)}"}
        end

      %{status_code: status_code, body: body} ->
        handle_error_response(status_code, body)
    end
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

        "ModelRetry" ->
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
