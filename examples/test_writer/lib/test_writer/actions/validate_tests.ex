defmodule TestWriter.Actions.ValidateTests do
  @moduledoc """
  Jido Action to run and validate generated tests.
  """

  use Jido.Action,
    name: "validate_tests",
    description: "Run tests and validate they pass",
    schema: [
      code: [type: :string, required: true, doc: "Test code to validate"],
      functions: [type: {:list, :map}, doc: "Original functions for coverage calculation"]
    ]

  alias TestWriter.{Compiler, Analyzer}

  @impl true
  def run(params, _context) do
    code = params.code

    with {:ok, quality} <- Compiler.validate_quality(code),
         {:ok, test_results} <- Compiler.run_tests(code) do
      coverage = calculate_coverage(params[:functions], code)

      {:ok,
       %{
         status: :validated,
         final_code: code,
         quality: quality,
         test_results: test_results,
         coverage: coverage
       }}
    else
      {:error, %{quality: :poor, issues: issues}} ->
        {:error, {:poor_quality, issues}}

      {:error, reason} ->
        {:error, {:validation_failed, reason}}
    end
  end

  defp calculate_coverage(nil, _code), do: nil

  defp calculate_coverage(functions, code) when is_list(functions) do
    test_names = Compiler.extract_test_names(code)
    tested_functions = estimate_tested_functions(functions, test_names)

    Analyzer.calculate_coverage(functions, tested_functions)
  end

  defp estimate_tested_functions(functions, test_names) do
    # Simple heuristic: check if function name appears in test name
    Enum.filter(functions, fn func ->
      func_name = to_string(func.name)

      Enum.any?(test_names, fn test_name ->
        String.contains?(String.downcase(test_name), String.downcase(func_name))
      end)
    end)
  end
end
