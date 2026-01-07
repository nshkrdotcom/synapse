defmodule TestWriter.SampleModules.Calculator do
  @moduledoc """
  A simple calculator module for testing TestWriter.
  """

  @doc """
  Adds two numbers together.
  """
  def add(a, b) do
    a + b
  end

  @doc """
  Subtracts the second number from the first.
  """
  def subtract(a, b) do
    a - b
  end

  @doc """
  Multiplies two numbers.
  """
  def multiply(a, b) do
    a * b
  end

  @doc """
  Divides the first number by the second.
  Returns an error if dividing by zero.
  """
  def divide(_a, 0), do: {:error, :division_by_zero}
  def divide(a, b), do: {:ok, a / b}

  # Private helper function (should be filtered out)
  defp validate_number(n) when is_number(n), do: :ok
  defp validate_number(_), do: {:error, :not_a_number}
end

defmodule TestWriter.SampleModules.StringHelper do
  @moduledoc """
  String manipulation utilities for testing.
  """

  @doc """
  Reverses a string.
  """
  def reverse(str) when is_binary(str) do
    String.reverse(str)
  end

  @doc """
  Converts a string to uppercase.
  """
  def upcase(str) when is_binary(str) do
    String.upcase(str)
  end

  @doc """
  Converts a string to lowercase.
  """
  def downcase(str) when is_binary(str) do
    String.downcase(str)
  end

  @doc """
  Checks if a string is a palindrome.
  """
  def palindrome?(str) when is_binary(str) do
    normalized = str |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
    normalized == String.reverse(normalized)
  end
end

defmodule TestWriter.SampleModules.ListHelper do
  @moduledoc """
  List manipulation utilities for testing.
  """

  @doc """
  Finds the sum of all numbers in a list.
  """
  def sum(list) when is_list(list) do
    Enum.sum(list)
  end

  @doc """
  Finds the maximum value in a list.
  """
  def max([]), do: nil
  def max(list) when is_list(list), do: Enum.max(list)

  @doc """
  Filters even numbers from a list.
  """
  def even_numbers(list) when is_list(list) do
    Enum.filter(list, &(rem(&1, 2) == 0))
  end

  @doc """
  Removes duplicates from a list.
  """
  def unique(list) when is_list(list) do
    Enum.uniq(list)
  end
end
