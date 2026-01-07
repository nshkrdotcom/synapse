defmodule DataPipeline.Providers.Gemini do
  @moduledoc """
  Gemini AI provider for fast classification and transformation.

  Uses Google's Gemini models via the gemini_ex SDK.
  """

  @behaviour DataPipeline.Providers.Behaviour

  require Logger

  @impl true
  def available? do
    case Application.get_env(:data_pipeline, :use_mocks) do
      true ->
        true

      _ ->
        api_key = Application.get_env(:data_pipeline, :gemini_api_key)
        !is_nil(api_key) && api_key != ""
    end
  end

  @impl true
  def generate(prompt, opts \\ []) do
    if Application.get_env(:data_pipeline, :use_mocks) do
      mock_generate(prompt, opts)
    else
      real_generate(prompt, opts)
    end
  end

  @impl true
  def generate_batch(prompts, opts \\ []) do
    if Application.get_env(:data_pipeline, :use_mocks) do
      results = Enum.map(prompts, &mock_generate(&1, opts))

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, Enum.map(results, fn {:ok, text} -> text end)}
      else
        {:error, :batch_generation_failed}
      end
    else
      # For real implementation, would batch requests
      results = Enum.map(prompts, &real_generate(&1, opts))

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, Enum.map(results, fn {:ok, text} -> text end)}
      else
        {:error, :batch_generation_failed}
      end
    end
  end

  # Real implementation using gemini_ex
  defp real_generate(prompt, opts) do
    model = Keyword.get(opts, :model, "gemini-1.5-flash")
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1024)

    case Gemini.generate(prompt,
           model: model,
           temperature: temperature,
           max_output_tokens: max_tokens
         ) do
      {:ok, response} ->
        text = extract_text(response)
        {:ok, text}

      {:error, reason} ->
        Logger.error("Gemini generation failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Gemini generation error: #{inspect(error)}")
      {:error, error}
  end

  # Mock implementation for testing
  defp mock_generate(prompt, _opts) do
    cond do
      String.contains?(prompt, "sentiment") ->
        {:ok, "positive"}

      String.contains?(prompt, "category") ->
        {:ok, "high_priority"}

      String.contains?(prompt, "intent") ->
        {:ok, "question"}

      String.contains?(prompt, "summarize") ->
        {:ok, "Summary: #{String.slice(prompt, 0..50)}..."}

      String.contains?(prompt, "translate") ->
        {:ok, "Translated text"}

      String.contains?(prompt, "enrich") ->
        {:ok, "Enriched data with additional context"}

      true ->
        {:ok, "Generated response for: #{String.slice(prompt, 0..30)}..."}
    end
  end

  defp extract_text(%{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
       }) do
    text
  end

  defp extract_text(%{candidates: [%{content: %{parts: [%{text: text} | _]}} | _]}) do
    text
  end

  defp extract_text(_), do: ""
end
