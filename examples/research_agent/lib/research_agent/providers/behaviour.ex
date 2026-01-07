defmodule ResearchAgent.Providers.Behaviour do
  @moduledoc """
  Behaviour for research provider adapters.

  Each provider adapter must implement this behaviour to provide
  a consistent interface for research operations.
  """

  alias ResearchAgent.Query

  @type search_result :: %{
          query: String.t(),
          results: [%{url: String.t(), title: String.t(), snippet: String.t()}],
          provider: atom(),
          metadata: map()
        }

  @type synthesis_result :: %{
          content: String.t(),
          provider: atom(),
          model: String.t() | nil,
          sources_cited: [String.t()],
          metadata: map()
        }

  @doc """
  Perform a web search using the provider's capabilities.
  """
  @callback search(Query.t(), keyword()) :: {:ok, search_result()} | {:error, term()}

  @doc """
  Synthesize research results into a coherent output.
  """
  @callback synthesize(list(map()), Query.t(), keyword()) ::
              {:ok, synthesis_result()} | {:error, term()}

  @doc """
  Check if this provider is available (has valid configuration).
  """
  @callback available?() :: boolean()

  @doc """
  Return the provider name atom.
  """
  @callback name() :: atom()
end
