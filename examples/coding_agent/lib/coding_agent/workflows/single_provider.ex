defmodule CodingAgent.Workflows.SingleProvider do
  @moduledoc """
  Execute a coding task with a single provider via Synapse workflow engine.

  This is the simplest workflow - just executes the task with the specified
  provider and returns the result.
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias CodingAgent.Actions.ExecuteProvider
  alias CodingAgent.Task

  @doc """
  Run a task with a single provider.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  @spec run(Task.t(), atom()) :: {:ok, map()} | {:error, term()}
  def run(%Task{} = task, provider) do
    spec =
      Spec.new(
        name: :single_provider_coding,
        description: "Execute coding task with #{provider}",
        metadata: %{task_id: task.id, provider: provider},
        steps: [
          [
            id: :execute,
            action: ExecuteProvider,
            params: %{task: Task.to_map(task), provider: provider},
            retry: [max_attempts: 3, backoff: 1000]
          ]
        ],
        outputs: [
          [key: :result, from: :execute]
        ]
      )

    case Engine.execute(spec,
           input: %{task: Task.to_map(task), provider: provider},
           context: %{request_id: task.id}
         ) do
      {:ok, %{outputs: outputs}} ->
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end
end
