defmodule DataPipeline.Transformers.Summarize do
  @moduledoc """
  Text summarization transformer using AI.

  Generates concise summaries of text content.
  """

  alias DataPipeline.Providers.Gemini

  @doc """
  Summarizes the given text.

  ## Options

    * `:max_length` - Maximum length of summary in words (default: 50)
    * `:style` - Summary style: `:brief`, `:detailed`, `:bullet_points` (default: :brief)

  ## Examples

      Summarize.transform("Long article text here...", max_length: 30)
      # => {:ok, "Brief summary of the article."}
  """
  @spec transform(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transform(text, opts \\ []) when is_binary(text) do
    max_length = Keyword.get(opts, :max_length, 50)
    style = Keyword.get(opts, :style, :brief)

    prompt = build_prompt(text, max_length, style)

    case Gemini.generate(prompt, temperature: 0.5, max_tokens: max_length * 2) do
      {:ok, summary} ->
        {:ok, String.trim(summary)}

      error ->
        error
    end
  end

  defp build_prompt(text, max_length, :brief) do
    """
    Provide a brief summary of the following text in #{max_length} words or less.

    Text: #{text}

    Summary:
    """
  end

  defp build_prompt(text, max_length, :detailed) do
    """
    Provide a detailed summary of the following text in #{max_length} words or less.
    Include key points and important details.

    Text: #{text}

    Summary:
    """
  end

  defp build_prompt(text, max_length, :bullet_points) do
    """
    Summarize the following text as bullet points (maximum #{max_length} words total).

    Text: #{text}

    Summary:
    """
  end
end
