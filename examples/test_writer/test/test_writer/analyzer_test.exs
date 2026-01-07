defmodule TestWriter.AnalyzerTest do
  use ExUnit.Case, async: true

  alias TestWriter.{Analyzer, Target}
  alias TestWriter.SampleModules.Calculator

  describe "analyze_loaded_module/1" do
    test "extracts public functions from loaded module" do
      {:ok, functions} = Analyzer.analyze_loaded_module(Calculator)

      assert is_list(functions)
      assert length(functions) > 0

      # Check that it found the main functions
      function_names = Enum.map(functions, & &1.name)
      assert :add in function_names
      assert :subtract in function_names
      assert :multiply in function_names
    end

    test "marks all functions as public" do
      {:ok, functions} = Analyzer.analyze_loaded_module(Calculator)

      assert Enum.all?(functions, fn f -> f.type == :public end)
    end

    test "includes arity information" do
      {:ok, functions} = Analyzer.analyze_loaded_module(Calculator)

      add_fn = Enum.find(functions, &(&1.name == :add))
      assert add_fn.arity == 2
    end
  end

  describe "analyze_source_code/1" do
    test "extracts functions from source code" do
      source = """
      defmodule TestModule do
        def public_func(x), do: x

        defp private_func(x), do: x * 2
      end
      """

      {:ok, functions} = Analyzer.analyze_source_code(source)

      assert length(functions) == 2
      assert Enum.any?(functions, &(&1.name == :public_func and &1.type == :public))
      assert Enum.any?(functions, &(&1.name == :private_func and &1.type == :private))
    end

    test "handles parse errors gracefully" do
      invalid_source = "defmodule Broken do def incomplete"

      {:error, {:parse_error, _}} = Analyzer.analyze_source_code(invalid_source)
    end
  end

  describe "filter_testable/1" do
    test "filters out internal functions" do
      functions = [
        %{name: :__struct__, arity: 0, type: :public, doc: nil, source: nil},
        %{name: :public_func, arity: 1, type: :public, doc: nil, source: nil},
        %{name: :__impl__, arity: 1, type: :public, doc: nil, source: nil}
      ]

      testable = Analyzer.filter_testable(functions)

      assert length(testable) == 1
      assert hd(testable).name == :public_func
    end

    test "filters out common callback functions" do
      functions = [
        %{name: :init, arity: 1, type: :public, doc: nil, source: nil},
        %{name: :handle_call, arity: 3, type: :public, doc: nil, source: nil},
        %{name: :my_function, arity: 0, type: :public, doc: nil, source: nil}
      ]

      testable = Analyzer.filter_testable(functions)

      assert length(testable) == 1
      assert hd(testable).name == :my_function
    end
  end

  describe "analyze_module/1" do
    test "analyzes loaded module via target" do
      target = Target.new(Calculator)

      {:ok, functions} = Analyzer.analyze_module(target)

      assert is_list(functions)
      assert length(functions) > 0
    end

    test "returns error for unavailable module" do
      target = Target.new(NonExistent.Module)

      {:error, {:module_not_available, _}} = Analyzer.analyze_module(target)
    end
  end

  describe "calculate_coverage/2" do
    test "calculates coverage percentage" do
      all_functions = [
        %{name: :func1, arity: 0},
        %{name: :func2, arity: 0},
        %{name: :func3, arity: 0},
        %{name: :func4, arity: 0}
      ]

      tested_functions = [
        %{name: :func1, arity: 0},
        %{name: :func2, arity: 0}
      ]

      coverage = Analyzer.calculate_coverage(all_functions, tested_functions)

      assert coverage.functions_total == 4
      assert coverage.functions_tested == 2
      assert coverage.percentage == 50.0
    end

    test "handles zero functions" do
      coverage = Analyzer.calculate_coverage([], [])

      assert coverage.functions_total == 0
      assert coverage.functions_tested == 0
      assert coverage.percentage == 0.0
    end
  end
end
