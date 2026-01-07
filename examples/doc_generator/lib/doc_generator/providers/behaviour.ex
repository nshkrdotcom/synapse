defmodule DocGenerator.Providers.Behaviour do
  @moduledoc """
  Behaviour for documentation provider adapters.

  Each provider specializes in different aspects of documentation:
  - Claude: Technical accuracy and comprehensive explanations
  - Codex: Code examples and usage patterns
  - Gemini: Clear, accessible explanations for broader audiences
  """

  alias DocGenerator.ModuleInfo

  @type doc_style :: :formal | :casual | :tutorial | :reference

  @type generation_opts :: [
          style: doc_style(),
          include_examples: boolean(),
          max_length: pos_integer() | nil
        ]

  @type result :: %{
          content: String.t(),
          provider: atom(),
          style: doc_style(),
          metadata: map()
        }

  @doc """
  Generate documentation for a module.
  """
  @callback generate_module_doc(ModuleInfo.t(), generation_opts()) ::
              {:ok, result()} | {:error, term()}

  @doc """
  Check if this provider is available (has valid configuration).
  """
  @callback available?() :: boolean()

  @doc """
  Return the provider name atom.
  """
  @callback name() :: atom()
end
