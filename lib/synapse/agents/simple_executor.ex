defmodule Synapse.Agents.SimpleExecutor do
  @moduledoc """
  A simple executor agent that runs Jido Actions.
  Tracks execution count as a basic example of stateful behavior.
  """

  use Jido.Agent,
    name: "simple_executor",
    description: "Executes actions and tracks execution count",
    actions: [
      Synapse.Actions.Echo
    ],
    schema: [
      execution_count: [type: :integer, default: 0, doc: "Number of actions executed"]
    ]

  require Logger

  @impl true
  def on_before_run(agent) do
    Logger.debug("SimpleExecutor: preparing to execute action")
    {:ok, agent}
  end

  @impl true
  def on_after_run(agent, _result, _directives) do
    Logger.debug("SimpleExecutor: action completed successfully")
    set(agent, %{execution_count: agent.state.execution_count + 1})
  end
end
