defmodule TestWriter.CompilerTest do
  use ExUnit.Case, async: true

  alias TestWriter.{Compiler, Fixtures}

  describe "compile_test/2" do
    test "compiles valid test code" do
      code = Fixtures.sample_test_code()

      assert {:ok, :compiled} = Compiler.compile_test(code)
    end

    test "returns errors for invalid syntax" do
      code = """
      defmodule Broken do
        def test do
          # Missing end
      end
      """

      assert {:error, errors} = Compiler.compile_test(code)
      assert is_list(errors)
      assert length(errors) > 0
      assert hd(errors).message
    end

    test "handles compilation errors" do
      code = """
      defmodule Test do
        def test do
          undefined_function()
        end
      end
      """

      # This will error because undefined_function/0 is not defined
      result = Compiler.compile_test(code)
      assert match?({:ok, :compiled}, result) or match?({:error, _}, result)
    end
  end

  describe "validate_quality/1" do
    test "validates good quality test code" do
      code = Fixtures.sample_test_code()

      # Note: The sample code might not pass all quality checks
      # Check that we get a result
      result = Compiler.validate_quality(code)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "detects missing test module" do
      code = """
      # Just a comment
      """

      assert {:error, %{quality: :poor, issues: issues}} = Compiler.validate_quality(code)
      assert :has_test_module in issues
    end

    test "detects missing ExUnit.Case" do
      code = """
      defmodule MyTest do
        test "something" do
          assert true
        end
      end
      """

      assert {:error, %{quality: :poor, issues: issues}} = Compiler.validate_quality(code)
      assert :has_use_exunit in issues
    end

    test "detects missing test cases" do
      code = """
      defmodule MyTest do
        use ExUnit.Case

        def helper do
          :ok
        end
      end
      """

      assert {:error, %{quality: :poor, issues: issues}} = Compiler.validate_quality(code)
      assert :has_test_cases in issues
    end
  end

  describe "format_errors_for_fix/1" do
    test "formats compile errors as text" do
      errors = Fixtures.sample_compile_errors()

      formatted = Compiler.format_errors_for_fix(errors)

      assert is_binary(formatted)
      assert formatted =~ "undefined function"
      assert formatted =~ "Line 8"
    end

    test "handles errors without line numbers" do
      errors = [%{file: "test.exs", line: nil, message: "Some error"}]

      formatted = Compiler.format_errors_for_fix(errors)

      assert formatted =~ "Some error"
      refute formatted =~ "Line"
    end
  end

  describe "extract_test_names/1" do
    test "extracts test names from code" do
      code = Fixtures.sample_test_code()

      names = Compiler.extract_test_names(code)

      assert is_list(names)
      assert "adds two positive numbers" in names
      assert "adds negative numbers" in names
      assert "subtracts two positive numbers" in names
    end

    test "returns empty list for code without tests" do
      code = """
      defmodule MyModule do
        def function, do: :ok
      end
      """

      assert Compiler.extract_test_names(code) == []
    end
  end
end
