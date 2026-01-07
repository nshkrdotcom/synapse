defmodule DataPipeline.Transformers.Enrich do
  @moduledoc """
  Data enrichment transformer using AI.

  Adds context, metadata, and additional information to data.
  """

  alias DataPipeline.Providers.Gemini

  @doc """
  Enriches the given text with additional context and information.

  ## Options

    * `:enrich_with` - Type of enrichment: `:context`, `:metadata`, `:keywords`, `:entities`
    * `:detail_level` - Level of detail: `:minimal`, `:standard`, `:comprehensive`

  ## Examples

      Enrich.transform("Apple released a new iPhone", enrich_with: :entities)
      # => {:ok, "Apple released a new iPhone [Entities: Apple (Company), iPhone (Product)]"}

      Enrich.transform("Quick meeting", enrich_with: :context)
      # => {:ok, "Quick meeting [Context: Brief synchronous discussion...]"}
  """
  @spec transform(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transform(text, opts \\ []) when is_binary(text) do
    enrich_type = Keyword.get(opts, :enrich_with, :context)
    detail_level = Keyword.get(opts, :detail_level, :standard)

    prompt = build_prompt(text, enrich_type, detail_level)

    case Gemini.generate(prompt, temperature: 0.6, max_tokens: 500) do
      {:ok, enriched} ->
        {:ok, String.trim(enriched)}

      error ->
        error
    end
  end

  defp build_prompt(text, :context, detail_level) do
    detail_instruction = detail_instruction(detail_level)

    """
    Add relevant context to the following text. #{detail_instruction}
    Format: Original text [Context: additional context here]

    Text: #{text}

    Enriched:
    """
  end

  defp build_prompt(text, :metadata, detail_level) do
    detail_instruction = detail_instruction(detail_level)

    """
    Add relevant metadata to the following text. #{detail_instruction}
    Include information like topic, category, audience, etc.
    Format: Original text [Metadata: key=value, key=value]

    Text: #{text}

    Enriched:
    """
  end

  defp build_prompt(text, :keywords, detail_level) do
    detail_instruction = detail_instruction(detail_level)

    """
    Extract and add relevant keywords to the following text. #{detail_instruction}
    Format: Original text [Keywords: keyword1, keyword2, keyword3]

    Text: #{text}

    Enriched:
    """
  end

  defp build_prompt(text, :entities, detail_level) do
    detail_instruction = detail_instruction(detail_level)

    """
    Extract and add named entities to the following text. #{detail_instruction}
    Include people, places, organizations, products, etc.
    Format: Original text [Entities: Name (Type), Name (Type)]

    Text: #{text}

    Enriched:
    """
  end

  defp detail_instruction(:minimal), do: "Be very concise."
  defp detail_instruction(:standard), do: "Provide a balanced level of detail."
  defp detail_instruction(:comprehensive), do: "Provide comprehensive detail."
end
