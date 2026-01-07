defmodule DocGenerator.Actions.GenerateModuleDoc do
  @moduledoc """
  Jido Action to generate documentation for a module using a specific provider.
  """

  use Jido.Action,
    name: "generate_module_doc",
    description: "Generate documentation for a module using AI provider",
    schema: [
      module: [type: :atom, required: true, doc: "Module to document"],
      module_info: [type: :map, required: false, doc: "Pre-analyzed module info"],
      provider: [type: :atom, required: true, doc: "Provider to use: :claude, :codex, :gemini"],
      style: [
        type: :atom,
        required: false,
        doc: "Documentation style: :formal, :casual, :tutorial, :reference"
      ],
      include_examples: [type: :boolean, required: false, doc: "Include code examples"]
    ]

  alias DocGenerator.{Analyzer, ModuleInfo, Providers}

  @impl true
  def run(params, _context) do
    module = params.module
    provider = params.provider
    style = params[:style] || :formal
    include_examples = params[:include_examples] || true

    # Get or analyze module info
    module_info =
      case params[:module_info] do
        %ModuleInfo{} = info ->
          info

        info_map when is_map(info_map) ->
          ModuleInfo.new(module,
            moduledoc: info_map[:moduledoc],
            functions: info_map[:functions] || [],
            types: info_map[:types] || [],
            callbacks: info_map[:callbacks] || [],
            behaviours: info_map[:behaviours] || []
          )

        _ ->
          case Analyzer.analyze_module(module) do
            {:ok, info} -> info
            {:error, reason} -> raise "Failed to analyze module: #{inspect(reason)}"
          end
      end

    provider_module = resolve_provider(provider)

    if provider_module.available?() do
      case provider_module.generate_module_doc(module_info,
             style: style,
             include_examples: include_examples
           ) do
        {:ok, result} ->
          {:ok,
           Map.merge(result, %{
             module: module,
             provider: provider
           })}

        {:error, reason} ->
          {:error, {:generation_failed, provider, reason}}
      end
    else
      {:error, {:provider_unavailable, provider}}
    end
  end

  defp resolve_provider(:claude), do: Providers.Claude
  defp resolve_provider(:codex), do: Providers.Codex
  defp resolve_provider(:gemini), do: Providers.Gemini
  defp resolve_provider(other), do: raise("Unknown provider: #{inspect(other)}")
end
