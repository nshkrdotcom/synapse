defmodule CodingAgent.Workflows.ParallelReview do
  @moduledoc """
  Run a task through multiple providers and aggregate results.

  This workflow executes the task with each specified provider (in parallel
  if the engine supports it), then aggregates the results into a combined
  response.
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias CodingAgent.Actions.{ExecuteProvider, AggregateResults}
  alias CodingAgent.Task

  @doc """
  Run a task with multiple providers and aggregate results.
  """
  @spec run(Task.t(), [atom()]) :: {:ok, map()} | {:error, term()}
  def run(%Task{} = task, providers) when is_list(providers) do
    task_map = Task.to_map(task)

    # Build dynamic steps for each provider
    provider_steps =
      Enum.map(providers, fn provider ->
        [
          id: :"#{provider}_execute",
          action: ExecuteProvider,
          params: %{task: task_map, provider: provider},
          on_error: :continue,
          retry: [max_attempts: 2, backoff: 500]
        ]
      end)

    # Aggregation step depends on all provider steps
    aggregate_step = [
      id: :aggregate,
      action: AggregateResults,
      requires: Enum.map(providers, &:"#{&1}_execute"),
      params: fn env ->
        results =
          Enum.map(providers, fn provider ->
            {provider, Map.get(env.results, :"#{provider}_execute")}
          end)

        %{results: results, task: task_map}
      end
    ]

    spec =
      Spec.new(
        name: :parallel_review,
        description: "Execute task with #{length(providers)} providers",
        metadata: %{task_id: task.id, providers: providers},
        steps: provider_steps ++ [aggregate_step],
        outputs: [
          [key: :combined, from: :aggregate, path: [:combined]],
          [key: :individual, from: :aggregate, path: [:individual]],
          [key: :summary, from: :aggregate]
        ]
      )

    case Engine.execute(spec,
           input: %{task: task_map, providers: providers},
           context: %{request_id: task.id}
         ) do
      {:ok, %{outputs: outputs}} ->
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end
end
