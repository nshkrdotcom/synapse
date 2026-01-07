defmodule TestWriter.Workflows.SimpleGenerate do
  @moduledoc """
  Simple workflow that generates tests without validation.

  This workflow:
  1. Analyzes the target module
  2. Generates tests using the provider
  3. Returns the generated code

  No compilation checking or fixing is performed.
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias TestWriter.Actions.{AnalyzeModule, GenerateTests}
  alias TestWriter.Target

  @doc """
  Run simple test generation workflow.

  ## Options

    * `:provider` - Provider to use (default: :codex)
    * `:context` - Additional context for generation
  """
  @spec run(Target.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Target{} = target, opts \\ []) do
    target_map = Target.to_map(target)
    provider = opts[:provider] || :codex
    context = opts[:context]

    spec =
      Spec.new(
        name: :simple_generate,
        description: "Simple test generation for #{inspect(target.module)}",
        metadata: %{target_id: target.id, provider: provider},
        steps: [
          # Step 1: Analyze module to extract functions
          [
            id: :analyze,
            action: AnalyzeModule,
            params: %{target: target_map},
            retry: [max_attempts: 1]
          ],

          # Step 2: Generate tests
          [
            id: :generate,
            action: GenerateTests,
            requires: [:analyze],
            params: fn env ->
              %{
                functions: env.results.analyze.testable_functions,
                module_name: target.module,
                provider: provider,
                context: context
              }
            end,
            retry: [max_attempts: 2, backoff: 1000]
          ]
        ],
        outputs: [
          [key: :code, from: :generate, path: [:code]],
          [key: :functions, from: :analyze, path: [:testable_functions]],
          [key: :function_count, from: :analyze, path: [:function_count]],
          [key: :provider, from: :generate, path: [:provider]]
        ]
      )

    case Engine.execute(spec,
           input: %{target: target_map},
           context: %{request_id: target.id}
         ) do
      {:ok, %{outputs: outputs}} ->
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end
end
