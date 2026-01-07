defmodule TestWriter.Actions.GenerateTests do
  @moduledoc """
  Jido Action to generate ExUnit tests using a provider.
  """

  use Jido.Action,
    name: "generate_tests",
    description: "Generate ExUnit tests for a list of functions",
    schema: [
      functions: [
        type: {:list, :map},
        required: true,
        doc: "List of function info maps to generate tests for"
      ],
      module_name: [type: :atom, doc: "Module name for context"],
      provider: [type: :atom, default: :codex, doc: "Provider to use for generation"],
      context: [type: :string, doc: "Additional context for test generation"]
    ]

  alias TestWriter.Providers

  @impl true
  def run(params, _context) do
    functions = params.functions
    provider = params[:provider] || :codex
    module = resolve_provider(provider)

    if module.available?() do
      opts = build_provider_opts(params)

      case module.generate_tests(functions, opts) do
        {:ok, result} ->
          {:ok,
           %{
             code: result.code,
             provider: result.provider,
             model: result.model,
             usage: result.usage,
             functions_count: length(functions)
           }}

        {:error, reason} ->
          {:error, {:generation_failed, reason}}
      end
    else
      {:error, {:provider_unavailable, provider}}
    end
  end

  defp resolve_provider(:codex), do: Providers.Codex

  defp build_provider_opts(params) do
    opts = []

    opts =
      if params[:module_name] do
        Keyword.put(opts, :module_name, params.module_name)
      else
        opts
      end

    opts =
      if params[:context] do
        Keyword.put(opts, :context, params.context)
      else
        opts
      end

    opts
  end
end
