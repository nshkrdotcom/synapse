defmodule DocGenerator.Actions.AnalyzeModule do
  @moduledoc """
  Jido Action to analyze a single module and extract its metadata.
  """

  use Jido.Action,
    name: "analyze_module",
    description: "Extract metadata from an Elixir module",
    schema: [
      module: [type: :atom, required: true, doc: "Module to analyze"]
    ]

  alias DocGenerator.Analyzer

  @impl true
  def run(params, _context) do
    module = params.module

    case Analyzer.analyze_module(module) do
      {:ok, module_info} ->
        {:ok,
         %{
           module_info: module_info,
           module: module,
           function_count: length(module_info.functions),
           type_count: length(module_info.types),
           has_docs: module_info.moduledoc != nil
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
