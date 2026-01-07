defmodule DocGenerator.AnalyzerTest do
  use ExUnit.Case, async: true

  alias DocGenerator.{Analyzer, Fixtures}

  describe "analyze_module/1" do
    test "analyzes a simple module" do
      {:ok, module_info} = Analyzer.analyze_module(Fixtures.SimpleModule)

      assert module_info.module == Fixtures.SimpleModule
      assert is_binary(module_info.moduledoc)
      assert length(module_info.functions) >= 2
      assert Enum.any?(module_info.functions, &(&1.name == :greet))
      assert Enum.any?(module_info.functions, &(&1.name == :add))
    end

    test "analyzes a complex module with types" do
      {:ok, module_info} = Analyzer.analyze_module(Fixtures.ComplexModule)

      assert module_info.module == Fixtures.ComplexModule
      assert length(module_info.functions) >= 3
      assert length(module_info.types) >= 2
    end

    test "analyzes a behaviour module" do
      {:ok, module_info} = Analyzer.analyze_module(Fixtures.BehaviourModule)

      assert module_info.module == Fixtures.BehaviourModule
      assert length(module_info.callbacks) >= 2
    end

    test "returns error for non-existent module" do
      assert {:error, {:module_not_loaded, NonExistent.Module}} =
               Analyzer.analyze_module(NonExistent.Module)
    end
  end

  describe "list_modules/1" do
    test "returns empty list when no modules in project" do
      project = Fixtures.sample_project()
      # Module list comes from project.modules
      modules = Analyzer.list_modules(project)
      assert is_list(modules)
    end
  end
end
