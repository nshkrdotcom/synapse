defmodule TestWriter.Actions.CompileTests do
  @moduledoc """
  Jido Action to compile generated test code and check for errors.
  """

  use Jido.Action,
    name: "compile_tests",
    description: "Compile test code to check for syntax and compilation errors",
    schema: [
      code: [type: :string, required: true, doc: "Test code to compile"],
      filename: [
        type: :string,
        default: "generated_test.exs",
        doc: "Filename for error reporting"
      ]
    ]

  alias TestWriter.Compiler

  @impl true
  def run(params, _context) do
    code = params.code
    opts = [filename: params[:filename] || "generated_test.exs"]

    case Compiler.compile_test(code, opts) do
      {:ok, :compiled} ->
        {:ok,
         %{
           status: :compiled,
           errors: [],
           code: code
         }}

      {:error, errors} ->
        # Return as success but with error status (on_error: :continue)
        {:ok,
         %{
           status: :error,
           errors: errors,
           code: code,
           error_summary: Compiler.format_errors_for_fix(errors)
         }}
    end
  end
end
