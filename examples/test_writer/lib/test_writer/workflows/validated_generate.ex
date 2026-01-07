defmodule TestWriter.Workflows.ValidatedGenerate do
  @moduledoc """
  Validated workflow that generates tests with compilation checking and fixing.

  This workflow:
  1. Analyzes the target module
  2. Generates tests using the provider
  3. Compiles the tests to check for errors
  4. Fixes tests if compilation fails (conditional)
  5. Validates the final tests

  The fix step is conditional based on compilation results.
  """

  alias Synapse.Workflow.{Spec, Engine}

  alias TestWriter.Actions.{
    AnalyzeModule,
    GenerateTests,
    CompileTests,
    FixTests,
    ValidateTests
  }

  alias TestWriter.Target

  @doc """
  Run validated test generation workflow with automatic fixing.

  ## Options

    * `:provider` - Provider to use (default: :codex)
    * `:context` - Additional context for generation
    * `:max_fix_attempts` - Maximum fix attempts (default: 3)
  """
  @spec run(Target.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Target{} = target, opts \\ []) do
    target_map = Target.to_map(target)
    provider = opts[:provider] || :codex
    context = opts[:context]

    max_fix_attempts =
      opts[:max_fix_attempts] || Application.get_env(:test_writer, :max_fix_attempts, 3)

    spec =
      Spec.new(
        name: :validated_generate,
        description: "Validated test generation for #{inspect(target.module)}",
        metadata: %{
          target_id: target.id,
          provider: provider,
          max_fix_attempts: max_fix_attempts
        },
        steps: build_steps(target, provider, context, max_fix_attempts),
        outputs: build_outputs()
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

  defp build_steps(target, provider, context, _max_fix_attempts) do
    [
      # Step 1: Analyze module to extract functions
      [
        id: :analyze,
        action: AnalyzeModule,
        params: %{target: Target.to_map(target)},
        retry: [max_attempts: 1],
        label: "Analyze module"
      ],

      # Step 2: Generate initial tests
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
        retry: [max_attempts: 2, backoff: 1000],
        label: "Generate tests"
      ],

      # Step 3: Compile tests to check for errors
      [
        id: :compile,
        action: CompileTests,
        requires: [:generate],
        params: fn env ->
          %{
            code: env.results.generate.code,
            filename: "#{target.module}_test.exs"
          }
        end,
        on_error: :continue,
        label: "Compile tests"
      ],

      # Step 4: Fix tests if compilation failed
      [
        id: :fix,
        action: FixTests,
        requires: [:compile],
        params: fn env ->
          case env.results.compile.status do
            :error ->
              %{
                code: env.results.generate.code,
                errors: env.results.compile.errors,
                error_summary: env.results.compile.error_summary,
                fix: true,
                provider: provider
              }

            _ ->
              %{
                code: env.results.compile.code,
                fix: false
              }
          end
        end,
        on_error: :continue,
        retry: [max_attempts: 2, backoff: 1000],
        label: "Fix tests if needed"
      ],

      # Step 5: Validate final tests
      [
        id: :validate,
        action: ValidateTests,
        requires: [:fix, :analyze],
        params: fn env ->
          # Use fixed code if fix was applied and successful, otherwise use original
          code =
            if env.results.fix.fixed do
              env.results.fix.code
            else
              env.results.compile.code
            end

          %{
            code: code,
            functions: env.results.analyze.testable_functions
          }
        end,
        on_error: :continue,
        label: "Validate tests"
      ]
    ]
  end

  defp build_outputs do
    [
      [
        key: :code,
        from: :validate,
        path: [:final_code],
        description: "Final validated test code"
      ],
      [
        key: :status,
        from: :validate,
        path: [:status],
        description: "Validation status"
      ],
      [
        key: :coverage,
        from: :validate,
        path: [:coverage],
        description: "Test coverage information"
      ],
      [
        key: :quality,
        from: :validate,
        path: [:quality],
        description: "Test quality assessment"
      ],
      [
        key: :compilation,
        from: :compile,
        path: [:status],
        description: "Compilation status"
      ],
      [
        key: :fixed,
        from: :fix,
        path: [:fixed],
        description: "Whether tests were fixed"
      ]
    ]
  end
end
