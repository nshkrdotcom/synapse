defmodule DataPipeline.Transformers.Translate do
  @moduledoc """
  Translation transformer using AI.

  Translates text between languages.
  """

  alias DataPipeline.Providers.Gemini

  @doc """
  Translates text to the target language.

  ## Options

    * `:to` - Target language (required)
    * `:from` - Source language (default: auto-detect)
    * `:formality` - Formality level: `:formal`, `:informal`, `:neutral` (default: :neutral)

  ## Examples

      Translate.transform("Hello, world!", to: "Spanish")
      # => {:ok, "Hola, mundo!"}

      Translate.transform("Bonjour", to: "English", from: "French")
      # => {:ok, "Hello"}
  """
  @spec transform(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transform(text, opts \\ []) when is_binary(text) do
    to_lang = Keyword.fetch!(opts, :to)
    from_lang = Keyword.get(opts, :from, "auto-detect")
    formality = Keyword.get(opts, :formality, :neutral)

    prompt = build_prompt(text, from_lang, to_lang, formality)

    case Gemini.generate(prompt, temperature: 0.3, max_tokens: String.length(text) * 2) do
      {:ok, translation} ->
        {:ok, String.trim(translation)}

      error ->
        error
    end
  end

  defp build_prompt(text, from_lang, to_lang, formality) do
    formality_instruction =
      case formality do
        :formal -> "Use formal language."
        :informal -> "Use informal/casual language."
        :neutral -> "Use neutral language."
      end

    from_instruction =
      if from_lang == "auto-detect" do
        ""
      else
        "The source language is #{from_lang}."
      end

    """
    Translate the following text to #{to_lang}. #{from_instruction} #{formality_instruction}
    Provide only the translation without any explanations.

    Text: #{text}

    Translation:
    """
  end
end
