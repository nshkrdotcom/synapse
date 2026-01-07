defmodule DocGenerator.Workflows.SingleModule do
  @moduledoc """
  Workflow to generate documentation for a single module using one provider.

  This is the simplest workflow that analyzes a module and generates
  documentation using a specified provider.
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias DocGenerator.Actions.{AnalyzeModule, GenerateModuleDoc}

  @doc """
  Generate documentation for a single module.

  ## Options

    * `:provider` - Provider to use (:claude, :codex, :gemini)
    * `:style` - Documentation style (:formal, :casual, :tutorial, :reference)
    * `:include_examples` - Include code examples (default: true)
  """
  @spec run(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(module, opts \\ []) when is_atom(module) do
    provider = Keyword.get(opts, :provider, :claude)
    style = Keyword.get(opts, :style, :formal)
    include_examples = Keyword.get(opts, :include_examples, true)

    spec =
      Spec.new(
        name: :single_module_doc,
        description: "Generate documentation for #{inspect(module)}",
        metadata: %{module: module, provider: provider, style: style},
        steps: [
          [
            id: :analyze,
            action: AnalyzeModule,
            params: %{module: module},
            label: "Analyzing module structure"
          ],
          [
            id: :generate,
            action: GenerateModuleDoc,
            requires: [:analyze],
            params: fn env ->
              %{
                module: module,
                module_info: get_in(env.results, [:analyze, :module_info]),
                provider: provider,
                style: style,
                include_examples: include_examples
              }
            end,
            label: "Generating documentation with #{provider}",
            retry: [max_attempts: 2, backoff: 1000]
          ]
        ],
        outputs: [
          [key: :content, from: :generate, path: [:content]],
          [key: :provider, from: :generate, path: [:provider]],
          [key: :module_info, from: :analyze, path: [:module_info]]
        ]
      )

    case Engine.execute(spec,
           input: %{module: module},
           context: %{request_id: "doc_#{module}_#{:rand.uniform(10000)}"}
         ) do
      {:ok, %{outputs: outputs}} ->
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end
end
