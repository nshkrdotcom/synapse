defmodule TestWriter.Providers.Codex do
  @moduledoc """
  Codex provider adapter using codex_sdk for test generation.

  Codex excels at:
  - Generating comprehensive test suites
  - Understanding code context and edge cases
  - Following ExUnit conventions
  """

  @behaviour TestWriter.Providers.Behaviour

  alias TestWriter.Target

  @impl true
  def name, do: :codex

  @impl true
  def available? do
    System.get_env("OPENAI_API_KEY") != nil
  end

  @impl true
  def generate_tests(functions, opts \\ []) when is_list(functions) do
    system_prompt = build_system_prompt()
    prompt = build_test_generation_prompt(functions, opts)

    codex_opts = build_codex_opts(system_prompt, opts)
    thread_opts = build_thread_opts(:generate_tests, opts)

    try do
      with {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
           {:ok, result} <- Codex.Thread.run(thread, prompt) do
        code = extract_code(result)

        {:ok,
         %{
           code: code,
           provider: :codex,
           model: codex_opts[:model] || "o4-mini",
           usage: result.usage,
           raw: result
         }}
      else
        {:error, reason} -> {:error, {:codex_error, reason}}
      end
    rescue
      e -> {:error, {:codex_exception, Exception.message(e)}}
    end
  end

  @impl true
  def fix_tests(code, errors, opts \\ []) do
    system_prompt = build_system_prompt()
    prompt = build_fix_prompt(code, errors, opts)

    codex_opts = build_codex_opts(system_prompt, opts)
    thread_opts = build_thread_opts(:fix_tests, opts)

    try do
      with {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
           {:ok, result} <- Codex.Thread.run(thread, prompt) do
        fixed_code = extract_code(result)

        {:ok,
         %{
           code: fixed_code,
           fixed: fixed_code != code,
           changes: extract_changes_description(result),
           provider: :codex,
           raw: result
         }}
      else
        {:error, reason} -> {:error, {:codex_error, reason}}
      end
    rescue
      e -> {:error, {:codex_exception, Exception.message(e)}}
    end
  end

  # Private helpers

  defp build_system_prompt do
    """
    You are an expert Elixir test writer. Your task is to generate high-quality ExUnit tests.

    Guidelines:
    - Use ExUnit.Case with appropriate async settings
    - Write descriptive test names that explain what is being tested
    - Include edge cases and error conditions
    - Use proper assertions (assert, refute, assert_raise, etc.)
    - Follow Elixir naming conventions
    - Add setup blocks when needed
    - Include doctests where applicable
    - Keep tests focused and readable

    Always return ONLY the Elixir test code, properly formatted.
    """
  end

  defp build_test_generation_prompt(functions, opts) do
    module_name = opts[:module_name] || "UnknownModule"
    context = opts[:context]

    functions_desc = format_functions_for_prompt(functions)

    """
    Generate comprehensive ExUnit tests for the following Elixir module functions:

    Module: #{inspect(module_name)}

    Functions to test:
    #{functions_desc}

    #{if context, do: "\nAdditional context:\n#{context}\n", else: ""}

    Requirements:
    - Create a test module named #{inspect(module_name)}Test
    - Use `use ExUnit.Case, async: true` unless there are side effects
    - Generate at least one test for each function
    - Test happy paths and edge cases
    - Use descriptive test names
    - Include proper setup if needed

    Return ONLY the complete test module code, ready to save as a .exs file.
    """
  end

  defp build_fix_prompt(code, errors, _opts) do
    """
    The following ExUnit test code has compilation or runtime errors.
    Please fix the errors and return the corrected code.

    Original test code:
    ```elixir
    #{code}
    ```

    Errors:
    #{errors}

    Requirements:
    - Fix all compilation and runtime errors
    - Maintain the test coverage and intent
    - Keep descriptive test names
    - Ensure the code follows ExUnit best practices

    Return ONLY the fixed test code, ready to compile and run.
    """
  end

  defp format_functions_for_prompt(functions) do
    functions
    |> Enum.map(fn func ->
      visibility = if func.type == :public, do: "public", else: "private"

      doc_line =
        if func.doc do
          "\n  Documentation: #{String.slice(func.doc, 0, 100)}"
        else
          ""
        end

      "- #{func.name}/#{func.arity} (#{visibility})#{doc_line}"
    end)
    |> Enum.join("\n")
  end

  defp build_codex_opts(system_prompt, opts) do
    %{
      model: Keyword.get(opts, :model, "o4-mini"),
      instructions: system_prompt
    }
  end

  defp build_thread_opts(operation, opts) do
    %{
      metadata: %{
        operation: operation,
        module: opts[:module_name]
      }
    }
  end

  defp extract_code(%{final_response: %{text: text}}) when is_binary(text) do
    # Extract code from markdown code blocks if present
    case Regex.run(~r/```(?:elixir)?\n(.+?)\n```/s, text) do
      [_, code] -> String.trim(code)
      nil -> String.trim(text)
    end
  end

  defp extract_code(%{final_response: response}) when is_map(response) do
    text = Map.get(response, :text, "")
    extract_code(%{final_response: %{text: text}})
  end

  defp extract_code(_), do: ""

  defp extract_changes_description(%{final_response: %{text: text}}) do
    # Try to extract explanation before code block
    case Regex.run(~r/^(.+?)```/s, text) do
      [_, description] -> String.trim(description)
      nil -> nil
    end
  end

  defp extract_changes_description(_), do: nil
end
