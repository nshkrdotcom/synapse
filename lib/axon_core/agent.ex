defmodule AxonCore.Agent do
  @moduledoc """
  Agent is a module that acts as a supervisor for the Agent children.
  It also defines the `child_spec/1` function which returns the specification
  for the Agent process. This is used by the Supervisor to start the Agent.
  """
  use Supervisor

  alias AxonCore.Agent.Server

  @doc """
  Starts the Agent supervisor.
  """
  def start_link(opts) do
    name = opts[:name] || raise ArgumentError, "name is required"
    Supervisor.start_link(__MODULE__, opts, name: String.to_atom("#{__MODULE__}.#{name}"))
  end

  @impl true
  def init(opts) do
    children = [
      {Task.Supervisor, name: String.to_atom("AxonCore.TaskSupervisor.#{opts[:name]}")},
      {Server, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the child specification for the Agent process.
  """
  def child_spec(opts) do
    %{
      id: opts[:name] || raise(ArgumentError, "name is required"),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end




# defmodule MultiAgent.Agent do
#   use GenServer
#   require Logger

#   def start_link(config) do
#     GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
#   end

#   defp via_tuple(agent_id) do
#     {:via, Registry, {MultiAgent.AgentRegistry, agent_id}}
#   end

#   @impl true
#   def init(config) do
#     # Start the Python process
#     port = start_python_process(config)

#     # Start a monitoring process for the port
#     Process.flag(:trap_exit, true)

#     {:ok, %{port: port, config: config}}
#   end

#   @impl true
#   def handle_info({port, {:data, data}}, %{port: port} = state) do
#     # Handle incoming data from Python process
#     Logger.info("Agent #{state.config.id} received: #{inspect(data)}")
#     {:noreply, state}
#   end

#   def handle_info({:EXIT, port, reason}, %{port: port} = state) do
#     Logger.error("Python process for agent #{state.config.id} exited: #{inspect(reason)}")
#     # Terminate the GenServer, letting the supervisor restart it
#     {:stop, :python_process_died, state}
#   end

#   @impl true
#   def terminate(_reason, %{port: port} = state) do
#     Logger.info("Terminating agent #{state.config.id}")
#     Port.close(port)
#   end

#   defp start_python_process(config) do
#     python_path = Path.join(File.cwd!(), "python")
#     Port.open(
#       {:spawn_executable, System.find_executable("python3")},
#       [
#         :binary,
#         :exit_status,
#         :use_stdio,
#         {:args, ["-u", Path.join(python_path, config.script)]},
#         {:env, [{"PYTHONPATH", python_path} | config.env || []]}
#       ]
#     )
#   end

#   # Client API

#   def send_message(agent_id, message) do
#     GenServer.cast(via_tuple(agent_id), {:send_message, message})
#   end

#   @impl true
#   def handle_cast({:send_message, message}, %{port: port} = state) do
#     Port.command(port, "#{message}\n")
#     {:noreply, state}
#   end
# end
