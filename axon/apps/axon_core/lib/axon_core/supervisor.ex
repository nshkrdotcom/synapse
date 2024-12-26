defmodule AxonCore.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Supervisor for each agent type
      {AxonCore.AgentProcess,
       python_module: "example_agent",
       model: "openai:gpt-4o",
       name: "python_agent_1"},
      # Potentially other supervisors for different agent types
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
