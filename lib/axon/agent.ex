defmodule Axon.Agent do
  @moduledoc """
  Agent is a module that acts as a supervisor for the Agent children.
  It also defines the `child_spec/1` function which returns the specification
  for the Agent process. This is used by the Supervisor to start the Agent.
  """
  use Supervisor

  alias Axon.Agent.Server

  @doc """
  Starts the Agent supervisor.
  """
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Task.Supervisor, name: Axon.TaskSupervisor},
      {Agent.Server, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the child specification for the Agent process.
  """
  def child_spec(opts) do
    %{
      id: "agent-#{opts[:name]}",
      start: {Agent.Server, :start_link, [opts]},
      type: :supervisor
    }
  end
end
