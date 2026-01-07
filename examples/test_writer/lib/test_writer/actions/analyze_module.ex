defmodule TestWriter.Actions.AnalyzeModule do
  @moduledoc """
  Jido Action to analyze a module and extract testable functions.
  """

  use Jido.Action,
    name: "analyze_module",
    description: "Analyze an Elixir module to extract functions for test generation",
    schema: [
      target: [
        type: :map,
        required: true,
        doc: "Target map with module, path, and optional source_code"
      ]
    ]

  alias TestWriter.{Target, Analyzer}

  @impl true
  def run(params, _context) do
    target = build_target(params.target)

    case Analyzer.analyze_module(target) do
      {:ok, all_functions} ->
        testable_functions = Analyzer.filter_testable(all_functions)

        {:ok,
         %{
           target: target,
           all_functions: all_functions,
           testable_functions: testable_functions,
           function_count: length(testable_functions)
         }}

      {:error, reason} ->
        {:error, {:analysis_failed, reason}}
    end
  end

  defp build_target(%Target{} = target), do: target

  defp build_target(params) when is_map(params) do
    Target.new(
      params[:module] || params["module"],
      path: params[:path] || params["path"],
      source_code: params[:source_code] || params["source_code"],
      metadata: params[:metadata] || params["metadata"]
    )
  end
end
