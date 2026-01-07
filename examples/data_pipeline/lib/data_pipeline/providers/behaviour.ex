defmodule DataPipeline.Providers.Behaviour do
  @moduledoc """
  Behaviour for AI provider implementations.

  Providers handle communication with AI services for classification,
  transformation, and other AI-powered operations.
  """

  @doc """
  Checks if the provider is available (e.g., API key configured).
  """
  @callback available?() :: boolean()

  @doc """
  Generates a completion for the given prompt.

  Returns the generated text or an error.
  """
  @callback generate(prompt :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Generates completions for a batch of prompts.

  More efficient than calling generate/2 multiple times.
  """
  @callback generate_batch(prompts :: [String.t()], opts :: keyword()) ::
              {:ok, [String.t()]} | {:error, term()}
end
