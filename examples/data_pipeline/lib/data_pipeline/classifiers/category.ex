defmodule DataPipeline.Classifiers.Category do
  @moduledoc """
  Category classifier using AI.

  Classifies data into high_priority or low_priority categories.
  """

  alias DataPipeline.Providers.Gemini

  @type category :: :high_priority | :low_priority

  @doc """
  Classifies the priority category of the given text.

  ## Examples

      Category.classify("URGENT: System down!")
      # => {:ok, :high_priority}

      Category.classify("Routine maintenance scheduled")
      # => {:ok, :low_priority}
  """
  @spec classify(String.t()) :: {:ok, category()} | {:error, term()}
  def classify(text) when is_binary(text) do
    prompt = build_prompt(text)

    case Gemini.generate(prompt, temperature: 0.3, max_tokens: 20) do
      {:ok, result} ->
        {:ok, parse_category(result)}

      error ->
        error
    end
  end

  @doc """
  Classifies a batch of texts.
  """
  @spec classify_batch([String.t()]) :: {:ok, [category()]} | {:error, term()}
  def classify_batch(texts) when is_list(texts) do
    prompts = Enum.map(texts, &build_prompt/1)

    case Gemini.generate_batch(prompts, temperature: 0.3, max_tokens: 20) do
      {:ok, results} ->
        {:ok, Enum.map(results, &parse_category/1)}

      error ->
        error
    end
  end

  defp build_prompt(text) do
    """
    Classify the priority of the following text as either "high_priority" or "low_priority".
    High priority items are urgent, time-sensitive, or critical.
    Low priority items are routine, informational, or can be handled later.

    Respond with only: high_priority or low_priority

    Text: #{text}

    Priority:
    """
  end

  defp parse_category(result) do
    normalized =
      result
      |> String.trim()
      |> String.downcase()

    if String.contains?(normalized, "high") do
      :high_priority
    else
      :low_priority
    end
  end
end
