defmodule DocGenerator.Actions.GenerateGuide do
  @moduledoc """
  Jido Action to generate usage guides for a project.
  """

  use Jido.Action,
    name: "generate_guide",
    description: "Generate usage guides and tutorials",
    schema: [
      project: [type: :map, required: true, doc: "Project information"],
      guide_type: [
        type: :atom,
        required: false,
        doc: "Type of guide: :getting_started, :api_reference, :tutorial"
      ],
      modules: [type: {:list, :atom}, required: false, doc: "Modules to include in guide"]
    ]

  @impl true
  def run(params, _context) do
    guide_type = params[:guide_type] || :getting_started
    project = params.project

    content = generate_guide_content(guide_type, project, params[:modules] || [])

    {:ok,
     %{
       content: content,
       guide_type: guide_type,
       format: :markdown,
       filename: "#{guide_type}.md"
     }}
  end

  defp generate_guide_content(:getting_started, project, _modules) do
    """
    # Getting Started with #{project[:name] || "This Project"}

    ## Introduction

    This guide will help you get started with using this library.

    ## Installation

    Add the dependency to your `mix.exs` file:

    ```elixir
    def deps do
      [
        {:#{snake_case(project[:name] || "project")}, "~> #{project[:version] || "0.1.0"}"}
      ]
    end
    ```

    ## Basic Usage

    Here's a simple example to get you started:

    ```elixir
    # TODO: Add usage examples
    ```

    ## Next Steps

    - Read the API Reference for detailed documentation
    - Check out the tutorials for more advanced usage
    - Explore the examples directory
    """
  end

  defp generate_guide_content(:api_reference, _project, modules) do
    """
    # API Reference

    ## Modules

    #{format_modules_for_reference(modules)}

    For detailed documentation of each module, please refer to the generated documentation.
    """
  end

  defp generate_guide_content(:tutorial, project, _modules) do
    """
    # #{project[:name] || "Project"} Tutorial

    ## Overview

    This tutorial will walk you through common use cases and patterns.

    ## Prerequisites

    - Elixir #{System.version()} or later
    - Basic understanding of Elixir

    ## Tutorial Steps

    ### Step 1: Setup

    Follow the installation instructions in the Getting Started guide.

    ### Step 2: Basic Operations

    TODO: Add tutorial content

    ## Conclusion

    You've learned the basics of using this library. Explore the API reference for more details.
    """
  end

  defp format_modules_for_reference([]), do: "No modules specified."

  defp format_modules_for_reference(modules) do
    modules
    |> Enum.map(fn mod -> "- `#{inspect(mod)}`" end)
    |> Enum.join("\n")
  end

  defp snake_case(name) when is_binary(name) do
    name
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  defp snake_case(name), do: snake_case(to_string(name))
end
