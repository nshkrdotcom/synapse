defmodule TestWriter.Fixtures do
  @moduledoc """
  Test fixtures for TestWriter tests.
  """

  @doc """
  Sample function info for testing.
  """
  def sample_functions do
    [
      %{
        name: :add,
        arity: 2,
        type: :public,
        doc: "Adds two numbers together",
        source: nil
      },
      %{
        name: :subtract,
        arity: 2,
        type: :public,
        doc: "Subtracts second number from first",
        source: nil
      },
      %{
        name: :multiply,
        arity: 2,
        type: :public,
        doc: nil,
        source: nil
      }
    ]
  end

  @doc """
  Sample generated test code.
  """
  def sample_test_code do
    """
    defmodule Calculator.Test do
      use ExUnit.Case, async: true

      describe "add/2" do
        test "adds two positive numbers" do
          assert Calculator.add(2, 3) == 5
        end

        test "adds negative numbers" do
          assert Calculator.add(-2, -3) == -5
        end

        test "adds zero" do
          assert Calculator.add(5, 0) == 5
        end
      end

      describe "subtract/2" do
        test "subtracts two positive numbers" do
          assert Calculator.subtract(5, 3) == 2
        end

        test "subtracts with negative result" do
          assert Calculator.subtract(3, 5) == -2
        end
      end

      describe "multiply/2" do
        test "multiplies two positive numbers" do
          assert Calculator.multiply(3, 4) == 12
        end

        test "multiplies by zero" do
          assert Calculator.multiply(5, 0) == 0
        end
      end
    end
    """
  end

  @doc """
  Sample test code with compilation errors.
  """
  def broken_test_code do
    """
    defmodule Calculator.Test do
      use ExUnit.Case, async: true

      test "broken test" do
        assert Calculator.invalid_function(1, 2) == 3
        # Missing end
    end
    """
  end

  @doc """
  Sample provider generation result.
  """
  def mock_generation_result do
    %{
      code: sample_test_code(),
      provider: :mock,
      model: "mock-model",
      usage: %{tokens: 100},
      raw: %{}
    }
  end

  @doc """
  Sample provider fix result.
  """
  def mock_fix_result do
    %{
      code: sample_test_code(),
      fixed: true,
      changes: "Fixed compilation errors",
      provider: :mock,
      raw: %{}
    }
  end

  @doc """
  Sample compile errors.
  """
  def sample_compile_errors do
    [
      %{
        file: "test.exs",
        line: 8,
        message: "undefined function invalid_function/2"
      },
      %{
        file: "test.exs",
        line: 9,
        message: "missing terminator: end"
      }
    ]
  end
end
