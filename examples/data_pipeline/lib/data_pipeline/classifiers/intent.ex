defmodule DataPipeline.Classifiers.Intent do
  @moduledoc """
  Intent classifier using AI.

  Classifies text by user intent: question, statement, request, or complaint.
  """

  alias DataPipeline.Providers.Gemini

  @type intent :: :question | :statement | :request | :complaint

  @doc """
  Classifies the intent of the given text.

  ## Examples

      Intent.classify("How do I reset my password?")
      # => {:ok, :question}

      Intent.classify("Please update my email address")
      # => {:ok, :request}
  """
  @spec classify(String.t()) :: {:ok, intent()} | {:error, term()}
  def classify(text) when is_binary(text) do
    prompt = build_prompt(text)

    case Gemini.generate(prompt, temperature: 0.3, max_tokens: 10) do
      {:ok, result} ->
        {:ok, parse_intent(result)}

      error ->
        error
    end
  end

  @doc """
  Classifies a batch of texts.
  """
  @spec classify_batch([String.t()]) :: {:ok, [intent()]} | {:error, term()}
  def classify_batch(texts) when is_list(texts) do
    prompts = Enum.map(texts, &build_prompt/1)

    case Gemini.generate_batch(prompts, temperature: 0.3, max_tokens: 10) do
      {:ok, results} ->
        {:ok, Enum.map(results, &parse_intent/1)}

      error ->
        error
    end
  end

  defp build_prompt(text) do
    """
    Classify the intent of the following text as one of: question, statement, request, or complaint.
    Respond with only one word.

    Text: #{text}

    Intent:
    """
  end

  defp parse_intent(result) do
    normalized =
      result
      |> String.trim()
      |> String.downcase()

    cond do
      String.contains?(normalized, "question") -> :question
      String.contains?(normalized, "request") -> :request
      String.contains?(normalized, "complaint") -> :complaint
      true -> :statement
    end
  end
end
