defmodule ReviewBot.Actions.ReviewCode do
  @moduledoc """
  Jido Action to review code with a specific provider.
  Broadcasts results via PubSub for real-time updates.
  """

  use Jido.Action,
    name: "review_code",
    description: "Review code with a specific AI provider",
    schema: [
      code: [type: :string, required: true, doc: "Code to review"],
      language: [type: :string, required: false, doc: "Programming language"],
      provider: [type: :atom, required: true, doc: "Provider: :claude, :codex, or :gemini"]
    ]

  alias ReviewBot.Providers

  @impl true
  def run(params, context) do
    code = params.code
    language = params[:language]
    provider = params.provider

    module = resolve_provider(provider)

    result =
      if module.available?() do
        module.review_code(code, language)
      else
        {:error, {:provider_unavailable, provider}}
      end

    # Broadcast to LiveView if review_id is in context
    case result do
      {:ok, review_result} ->
        broadcast_result(context, provider, review_result)
        {:ok, review_result}

      error ->
        error
    end
  end

  defp resolve_provider(:claude), do: Providers.Claude
  defp resolve_provider(:codex), do: Providers.Codex
  defp resolve_provider(:gemini), do: Providers.Gemini

  defp broadcast_result(context, provider, result) do
    review_id = context[:review_id]

    if review_id do
      Phoenix.PubSub.broadcast(
        ReviewBot.PubSub,
        "review:#{review_id}",
        {:provider_result, provider, result}
      )
    end
  end
end
