defmodule ReviewBot.Providers.Behaviour do
  @moduledoc """
  Behaviour for code review providers.
  """

  @doc """
  Returns true if the provider is available (API keys configured, etc.).
  """
  @callback available?() :: boolean()

  @doc """
  Reviews code and returns analysis results.
  """
  @callback review_code(code :: String.t(), language :: String.t() | nil) ::
              {:ok, map()} | {:error, term()}
end
