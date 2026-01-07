defmodule TestWriter.Providers.Behaviour do
  @moduledoc """
  Behaviour for test generation providers.

  Each provider must implement this behaviour to provide a consistent
  interface for test generation operations.
  """

  alias TestWriter.Target

  @type generation_result :: %{
          code: String.t(),
          provider: atom(),
          model: String.t() | nil,
          usage: map() | nil,
          raw: term()
        }

  @type fix_result :: %{
          code: String.t(),
          fixed: boolean(),
          changes: String.t() | nil,
          provider: atom(),
          raw: term()
        }

  @doc """
  Generate tests for the given functions.
  """
  @callback generate_tests([Target.function_info()], keyword()) ::
              {:ok, generation_result()} | {:error, term()}

  @doc """
  Fix failing or non-compiling tests.
  """
  @callback fix_tests(String.t(), String.t(), keyword()) ::
              {:ok, fix_result()} | {:error, term()}

  @doc """
  Check if this provider is available (has valid configuration).
  """
  @callback available?() :: boolean()

  @doc """
  Return the provider name atom.
  """
  @callback name() :: atom()
end
