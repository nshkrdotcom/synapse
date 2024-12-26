defmodule AxonCore.AgentProcess do
  use GenServer

  alias AxonCore.HTTPClient
  alias AxonCore.JSONCodec
  alias AxonCore.Types, as: T

  @default_timeout 60_000

  def start_link(python_module: python_module, model: model, name: name) do
    GenServer.start_link(__MODULE__, %{python_module: python_module, model: model, port: get_free_port(), name: name},
      name: name
    )
  end

  def get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, reuseaddr: true, active: false])
    {_, port} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  @impl true
  def init(state) do
    # Start the Python agent process using Ports
    # Pass configuration as environment variables or command-line arguments
    port =
      Port.open(
        {:spawn_executable, "./python_agent_runner.sh"},
        [
          {:args, [state.python_module, Integer.to_string(state.port), state.model]},
          {:cd, "./python_agents"},
          {:env, ["OPENAI_API_KEY=#{System.get_env("OPENAI_API_KEY")}"]},
          :binary,
          :use_stdio,
          :exit_status
        ]
      )

    {:ok, %{state | port: port}}
  end

  def send_message(agent_name, message) do
    GenServer.call(agent_name, {:send_message, message}, @default_timeout)
  end




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
      # Process the response, which could be streamed or a complete response
      case response do
        %{status_code: 200, body: body} ->
            # Decode the JSON response
            decoded_response = JSONCodec.decode(body)

            # Route the response based on your application logic
            # ...

            {:reply, {:ok, decoded_response}, state}

        %{status_code: status_code, body: body} -> # we will need custom error handling here
          {:reply, {:error, "Non-200 response from Python agent: #{status_code}", body}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
