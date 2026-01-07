defmodule TestWriter do
  @moduledoc """
  TestWriter - Automated ExUnit test generation for Elixir modules.

  TestWriter uses the Synapse framework to orchestrate AI-powered test generation
  with validation and automatic fixing capabilities.

  ## Features

  - Analyzes modules to extract testable functions
  - Generates comprehensive ExUnit tests using AI providers
  - Compiles and validates generated tests
  - Automatically fixes compilation errors
  - Provides test coverage analysis

  ## Usage

      # Simple generation without validation
      {:ok, result} = TestWriter.generate_tests(MyModule)
      File.write!("test/my_module_test.exs", result.code)

      # Validated generation with automatic fixing
      {:ok, result} = TestWriter.generate_tests(MyModule, validated: true)
      File.write!("test/my_module_test.exs", result.code)

      # With source code instead of loaded module
      target = TestWriter.Target.new(MyModule, source_code: source)
      {:ok, result} = TestWriter.generate_tests(target)
  """

  alias TestWriter.{Target, Workflows}

  @type generation_options :: [
          validated: boolean(),
          provider: :codex,
          context: String.t(),
          max_fix_attempts: pos_integer()
        ]

  @doc """
  Generate tests for a module or target.

  ## Options

    * `:validated` - Use validated workflow with compilation checking (default: false)
    * `:provider` - AI provider to use (default: :codex)
    * `:context` - Additional context for generation
    * `:max_fix_attempts` - Maximum fix attempts for validated workflow (default: 3)

  ## Examples

      # Simple generation
      {:ok, %{code: code}} = TestWriter.generate_tests(MyModule)

      # Validated generation
      {:ok, result} = TestWriter.generate_tests(MyModule, validated: true)

      # With custom provider and context
      {:ok, result} = TestWriter.generate_tests(
        MyModule,
        validated: true,
        provider: :codex,
        context: "This module handles user authentication"
      )
  """
  @spec generate_tests(module() | Target.t(), generation_options()) ::
          {:ok, map()} | {:error, term()}
  def generate_tests(module_or_target, opts \\ [])

  def generate_tests(%Target{} = target, opts) do
    if opts[:validated] do
      Workflows.ValidatedGenerate.run(target, opts)
    else
      Workflows.SimpleGenerate.run(target, opts)
    end
  end

  def generate_tests(module, opts) when is_atom(module) do
    target = Target.new(module)
    generate_tests(target, opts)
  end

  @doc """
  Generate tests and save to file.

  Returns the file path on success.

  ## Examples

      {:ok, path} = TestWriter.generate_and_save(MyModule, "test/my_module_test.exs")
  """
  @spec generate_and_save(module() | Target.t(), String.t(), generation_options()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_and_save(module_or_target, output_path, opts \\ []) do
    case generate_tests(module_or_target, opts) do
      {:ok, %{code: code}} ->
        case File.write(output_path, code) do
          :ok -> {:ok, output_path}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Analyze a module without generating tests.

  Useful for understanding what functions would be tested.

  ## Examples

      {:ok, functions} = TestWriter.analyze(MyModule)
      Enum.each(functions, fn func ->
        IO.puts("\#{func.name}/\#{func.arity}")
      end)
  """
  @spec analyze(module() | Target.t()) :: {:ok, [Target.function_info()]} | {:error, term()}
  def analyze(module_or_target)

  def analyze(%Target{} = target) do
    alias TestWriter.Analyzer

    case Analyzer.analyze_module(target) do
      {:ok, all_functions} ->
        {:ok, Analyzer.filter_testable(all_functions)}

      error ->
        error
    end
  end

  def analyze(module) when is_atom(module) do
    target = Target.new(module)
    analyze(target)
  end

  @doc """
  Check if a provider is available for use.

  ## Examples

      if TestWriter.provider_available?(:codex) do
        # Use codex
      end
  """
  @spec provider_available?(atom()) :: boolean()
  def provider_available?(provider) do
    case provider do
      :codex -> TestWriter.Providers.Codex.available?()
      _ -> false
    end
  end
end
