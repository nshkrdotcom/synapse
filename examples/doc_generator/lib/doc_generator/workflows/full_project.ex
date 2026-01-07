defmodule DocGenerator.Workflows.FullProject do
  @moduledoc """
  Workflow to generate documentation for an entire project.

  Analyzes multiple modules in parallel and generates documentation using
  multiple providers, similar to the ParallelReview pattern in coding_agent.
  """

  alias Synapse.Workflow.{Spec, Engine}

  alias DocGenerator.Actions.{
    AnalyzeProject,
    GenerateModuleDoc,
    AggregateDocs,
    GenerateReadme
  }

  @doc """
  Generate comprehensive documentation for a project.

  ## Options

    * `:modules` - Specific modules to document (default: all discovered)
    * `:providers` - List of providers to use (default: [:claude, :codex, :gemini])
    * `:style` - Documentation style (default: :formal)
    * `:include_examples` - Include code examples (default: true)
    * `:parallel` - Generate docs in parallel (default: true)
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(project_path, opts \\ []) when is_binary(project_path) do
    modules = Keyword.get(opts, :modules, [])
    providers = Keyword.get(opts, :providers, [:claude, :codex, :gemini])
    style = Keyword.get(opts, :style, :formal)
    _include_examples = Keyword.get(opts, :include_examples, true)

    # Build workflow steps
    analyze_project_step = [
      id: :analyze_project,
      action: AnalyzeProject,
      params: %{path: project_path, modules: modules},
      label: "Analyzing project structure"
    ]

    # For each module, create analysis and generation steps
    # We'll use a simpler approach: analyze project, then generate docs
    spec =
      Spec.new(
        name: :full_project_doc,
        description: "Generate documentation for project at #{project_path}",
        metadata: %{
          project_path: project_path,
          providers: providers,
          style: style
        },
        steps: [analyze_project_step],
        outputs: [
          [key: :project, from: :analyze_project, path: [:project]],
          [key: :module_count, from: :analyze_project, path: [:module_count]]
        ]
      )

    case Engine.execute(spec,
           input: %{path: project_path},
           context: %{request_id: "project_doc_#{:rand.uniform(10000)}"}
         ) do
      {:ok, %{outputs: outputs}} ->
        # In a full implementation, we'd continue with per-module documentation
        # For now, return the analysis
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end

  @doc """
  Generate documentation for multiple modules in parallel.

  This demonstrates the parallel execution pattern where each module is
  documented by multiple providers simultaneously.
  """
  @spec run_parallel(String.t(), [module()], keyword()) :: {:ok, map()} | {:error, term()}
  def run_parallel(project_path, modules, opts \\ []) when is_list(modules) do
    providers = Keyword.get(opts, :providers, [:claude, :codex, :gemini])
    style = Keyword.get(opts, :style, :formal)
    include_examples = Keyword.get(opts, :include_examples, true)

    # Build steps for each module + provider combination
    module_provider_steps =
      for module <- modules, provider <- providers do
        [
          id: :"#{module}_#{provider}",
          action: GenerateModuleDoc,
          params: %{
            module: module,
            provider: provider,
            style: style,
            include_examples: include_examples
          },
          label: "Generating docs for #{inspect(module)} with #{provider}",
          on_error: :continue,
          retry: [max_attempts: 2, backoff: 500]
        ]
      end

    # Aggregate steps for each module
    aggregate_steps =
      for module <- modules do
        provider_step_ids = Enum.map(providers, &:"#{module}_#{&1}")

        [
          id: :"aggregate_#{module}",
          action: AggregateDocs,
          requires: provider_step_ids,
          params: fn env ->
            results =
              Enum.map(providers, fn provider ->
                step_id = :"#{module}_#{provider}"
                {provider, Map.get(env.results, step_id)}
              end)

            %{
              results: results,
              module: module,
              strategy: :combine
            }
          end,
          label: "Aggregating docs for #{inspect(module)}"
        ]
      end

    # Generate README after all modules are documented
    readme_step = [
      id: :generate_readme,
      action: GenerateReadme,
      requires: Enum.map(modules, &:"aggregate_#{&1}"),
      params: fn env ->
        module_docs =
          Enum.map(modules, fn module ->
            Map.get(env.results, :"aggregate_#{module}")
          end)

        %{
          project: %{path: project_path, name: extract_project_name(project_path)},
          module_docs: module_docs
        }
      end,
      label: "Generating README"
    ]

    all_steps = module_provider_steps ++ aggregate_steps ++ [readme_step]

    # Build outputs for each module
    module_outputs =
      for module <- modules do
        [key: :"module_#{module}", from: :"aggregate_#{module}"]
      end

    readme_output = [key: :readme, from: :generate_readme]

    spec =
      Spec.new(
        name: :parallel_project_doc,
        description: "Parallel documentation for #{length(modules)} modules",
        metadata: %{
          project_path: project_path,
          modules: modules,
          providers: providers
        },
        steps: all_steps,
        outputs: module_outputs ++ [readme_output]
      )

    case Engine.execute(spec,
           input: %{project_path: project_path, modules: modules},
           context: %{request_id: "parallel_doc_#{:rand.uniform(10000)}"}
         ) do
      {:ok, %{outputs: outputs}} ->
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end

  defp extract_project_name(path) do
    path
    |> Path.basename()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
