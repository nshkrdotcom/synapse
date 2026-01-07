defmodule CodingAgent.Providers.Behaviour do
  @moduledoc """
  Behaviour for provider adapters.

  Each provider adapter must implement this behaviour to provide
  a consistent interface for task execution.
  """

  alias CodingAgent.Task

  @type result :: %{
          content: String.t(),
          provider: atom(),
          model: String.t() | nil,
          usage: map() | nil,
          raw: term()
        }

  @doc """
  Execute a coding task and return the result.
  """
  @callback execute(Task.t(), keyword()) :: {:ok, result()} | {:error, term()}

  @doc """
  Check if this provider is available (has valid configuration).
  """
  @callback available?() :: boolean()

  @doc """
  Return the provider name atom.
  """
  @callback name() :: atom()
end
