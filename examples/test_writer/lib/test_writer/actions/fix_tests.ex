defmodule TestWriter.Actions.FixTests do
  @moduledoc """
  Jido Action to fix failing or non-compiling tests.
  """

  use Jido.Action,
    name: "fix_tests",
    description: "Fix compilation or runtime errors in generated tests",
    schema: [
      code: [type: :string, required: true, doc: "Original test code"],
      errors: [type: {:list, :map}, doc: "List of compilation errors"],
      error_summary: [type: :string, doc: "Formatted error summary"],
      fix: [type: :boolean, default: true, doc: "Whether to attempt fix"],
      provider: [type: :atom, default: :codex, doc: "Provider to use for fixing"]
    ]

  alias TestWriter.Providers

  @impl true
  def run(params, _context) do
    # If fix is false, just return the original code
    if !params[:fix] do
      {:ok, %{code: params.code, fixed: false}}
    else
      do_fix(params)
    end
  end

  defp do_fix(params) do
    code = params.code
    error_summary = params[:error_summary] || format_errors(params[:errors])
    provider = params[:provider] || :codex
    module = resolve_provider(provider)

    if module.available?() do
      case module.fix_tests(code, error_summary, []) do
        {:ok, result} ->
          {:ok,
           %{
             code: result.code,
             fixed: result.fixed,
             changes: result.changes,
             provider: result.provider
           }}

        {:error, _reason} ->
          # Return original code if fix fails
          {:ok,
           %{
             code: code,
             fixed: false,
             error: :fix_failed
           }}
      end
    else
      # Return original code if provider unavailable
      {:ok, %{code: code, fixed: false, error: :provider_unavailable}}
    end
  end

  defp resolve_provider(:codex), do: Providers.Codex

  defp format_errors(nil), do: "Unknown errors"

  defp format_errors(errors) when is_list(errors) do
    TestWriter.Compiler.format_errors_for_fix(errors)
  end

  defp format_errors(_), do: "Unknown errors"
end
