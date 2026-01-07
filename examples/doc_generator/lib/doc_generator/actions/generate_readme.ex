defmodule DocGenerator.Actions.GenerateReadme do
  @moduledoc """
  Jido Action to generate a README.md for a project.
  """

  use Jido.Action,
    name: "generate_readme",
    description: "Generate a README.md for an Elixir project",
    schema: [
      project: [type: :map, required: true, doc: "Project information"],
      module_docs: [type: {:list, :map}, required: false, doc: "Generated module documentation"],
      provider: [type: :atom, required: false, doc: "Provider to use for generation"]
    ]

  @impl true
  def run(params, _context) do
    project = params.project
    module_docs = params[:module_docs] || []

    # For now, generate a basic README
    # In a real implementation, this could use AI to create a comprehensive README
    readme_content = build_readme(project, module_docs)

    {:ok,
     %{
       content: readme_content,
       format: :markdown,
       filename: "README.md"
     }}
  end

  defp build_readme(project, module_docs) do
    """
    # #{project[:name] || "Elixir Project"}

    #{if project[:version], do: "Version: #{project[:version]}\n", else: ""}
    ## Overview

    This project contains #{length(module_docs)} documented modules.

    ## Modules

    #{format_module_list(module_docs)}

    ## Installation

    If available in Hex, the package can be installed by adding `#{snake_case(project[:name] || "project")}` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [
        {:#{snake_case(project[:name] || "project")}, "~> #{project[:version] || "0.1.0"}"}
      ]
    end
    ```

    ## Documentation

    Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc).

    ## License

    Copyright (c) #{DateTime.utc_now().year}
    """
  end

  defp format_module_list([]), do: "No modules documented yet."

  defp format_module_list(module_docs) do
    module_docs
    |> Enum.map(fn doc ->
      module_name = doc[:module] || "Unknown"
      "- `#{inspect(module_name)}`"
    end)
    |> Enum.join("\n")
  end

  defp snake_case(nil), do: "project"

  defp snake_case(name) when is_binary(name) do
    name
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  defp snake_case(name), do: snake_case(to_string(name))
end
