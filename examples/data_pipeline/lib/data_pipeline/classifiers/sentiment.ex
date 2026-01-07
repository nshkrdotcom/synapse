defmodule DataPipeline.Classifiers.Sentiment do
  @moduledoc """
  Sentiment classifier using AI.

  Classifies text as positive, negative, or neutral.
  """

  alias DataPipeline.Providers.Gemini

  @type sentiment :: :positive | :negative | :neutral

  @doc """
  Classifies the sentiment of the given text.

  ## Examples

      Sentiment.classify("I love this product!")
      # => {:ok, :positive}

      Sentiment.classify("This is terrible")
      # => {:ok, :negative}
  """
  @spec classify(String.t()) :: {:ok, sentiment()} | {:error, term()}
  def classify(text) when is_binary(text) do
    prompt = build_prompt(text)

    case Gemini.generate(prompt, temperature: 0.3, max_tokens: 10) do
      {:ok, result} ->
        {:ok, parse_sentiment(result)}

      error ->
        error
    end
  end

  @doc """
  Classifies a batch of texts.
  """
  @spec classify_batch([String.t()]) :: {:ok, [sentiment()]} | {:error, term()}
  def classify_batch(texts) when is_list(texts) do
    prompts = Enum.map(texts, &build_prompt/1)

    case Gemini.generate_batch(prompts, temperature: 0.3, max_tokens: 10) do
      {:ok, results} ->
        {:ok, Enum.map(results, &parse_sentiment/1)}

      error ->
        error
    end
  end

  defp build_prompt(text) do
    """
    Classify the sentiment of the following text as either "positive", "negative", or "neutral".
    Respond with only one word: positive, negative, or neutral.

    Text: #{text}

    Sentiment:
    """
  end

  defp parse_sentiment(result) do
    normalized =
      result
      |> String.trim()
      |> String.downcase()

    cond do
      String.contains?(normalized, "positive") -> :positive
      String.contains?(normalized, "negative") -> :negative
      true -> :neutral
    end
  end
end
