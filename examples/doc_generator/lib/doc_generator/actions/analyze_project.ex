defmodule DocGenerator.Actions.AnalyzeProject do
  @moduledoc """
  Jido Action to analyze a project directory and discover modules.
  """

  use Jido.Action,
    name: "analyze_project",
    description: "Analyze an Elixir project and discover its modules",
    schema: [
      path: [type: :string, required: true, doc: "Path to the project directory"],
      modules: [
        type: {:list, :atom},
        required: false,
        doc: "Specific modules to analyze (if empty, discovers all)"
      ]
    ]

  alias DocGenerator.{Project, Analyzer}

  @impl true
  def run(params, _context) do
    path = params.path
    specified_modules = params[:modules] || []

    case Project.from_directory(path) do
      {:ok, project} ->
        modules =
          if Enum.empty?(specified_modules) do
            Analyzer.list_modules(project)
          else
            specified_modules
          end

        updated_project = %{project | modules: modules}

        {:ok,
         %{
           project: updated_project,
           module_count: length(modules),
           modules: modules
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
