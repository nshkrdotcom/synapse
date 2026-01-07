defmodule TestWriterTest do
  use ExUnit.Case, async: true

  alias TestWriter.{Target, SampleModules}

  describe "analyze/1" do
    test "analyzes a loaded module" do
      {:ok, functions} = TestWriter.analyze(SampleModules.Calculator)

      assert is_list(functions)
      assert length(functions) > 0

      # Verify we got expected functions
      function_names = Enum.map(functions, & &1.name)
      assert :add in function_names
      assert :subtract in function_names
    end

    test "analyzes a target" do
      target = Target.new(SampleModules.Calculator)

      {:ok, functions} = TestWriter.analyze(target)

      assert is_list(functions)
      assert length(functions) > 0
    end

    test "returns error for non-existent module" do
      {:error, _} = TestWriter.analyze(NonExistent.Module)
    end
  end

  describe "provider_available?/1" do
    test "checks if provider is available" do
      # This will check for OPENAI_API_KEY
      result = TestWriter.provider_available?(:codex)
      assert is_boolean(result)
    end

    test "returns false for unknown provider" do
      refute TestWriter.provider_available?(:unknown)
    end
  end
end
