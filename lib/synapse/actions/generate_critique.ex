defmodule Synapse.Actions.GenerateCritique do
  @moduledoc """
  Generates actionable critique or follow-up suggestions by delegating to an HTTP LLM endpoint.

  ## Compensation

  This action implements automatic compensation on LLM failures:

  - Logs failure context for debugging
  - Emits telemetry event for monitoring
  - Returns structured compensation result
  - Enables retry via Jido's compensation system

  Compensation is triggered on any error from ReqLLM.chat_completion/2.
  """

  use Jido.Action,
    name: "generate_critique",
    description: "Uses an LLM (via Req) to produce review suggestions",
    compensation: [
      enabled: true,
      max_retries: 2,
      timeout: 5_000
    ],
    schema: [
      prompt: [type: :string, required: true, doc: "Primary user prompt"],
      messages: [
        type: {:list, :map},
        default: [],
        doc: "Additional conversation messages already exchanged with the model"
      ],
      temperature: [
        type: {:or, [:float, nil]},
        default: nil,
        doc: "Sampling temperature passed through to the LLM provider"
      ],
      max_tokens: [
        type: {:or, [:integer, nil]},
        default: nil,
        doc: "Optional token cap for the response"
      ],
      profile: [
        type: {:or, [:atom, :string]},
        default: nil,
        doc: "Optional LLM profile name (e.g. :openai, :gemini)"
      ]
    ]

  alias Jido.Error
  alias Synapse.{ReqLLM, Telemetry}

  require Logger

  @impl true
  def run(params, context) do
    llm_params = Map.take(params, [:prompt, :messages, :temperature, :max_tokens])
    profile = Map.get(params, :profile)
    request_id = Map.get(context, :request_id, generate_request_id())

    Logger.debug("Starting LLM critique request",
      request_id: request_id,
      profile: profile,
      prompt_length: String.length(params.prompt)
    )

    llm = Application.get_env(:synapse, :req_llm_module, ReqLLM)

    case llm.chat_completion(llm_params, profile: profile) do
      {:ok, response} ->
        Logger.debug("LLM critique completed",
          request_id: request_id,
          tokens: get_in(response, [:metadata, :total_tokens])
        )

        {:ok, response}

      {:error, %Error{} = error} ->
        Logger.warning("LLM critique failed",
          request_id: request_id,
          error_type: error.type,
          error_message: error.message
        )

        {:error, error}
    end
  end

  @impl true
  def on_error(failed_params, error, context, _opts) do
    request_id = Map.get(context, :request_id, "unknown")
    profile = Map.get(failed_params, :profile, "unknown")

    Logger.warning("Compensating for LLM failure",
      request_id: request_id,
      profile: profile,
      error_type: error.type,
      error_message: error.message
    )

    # Emit telemetry event for monitoring
    Telemetry.emit_compensation(
      request_id: request_id,
      profile: profile,
      error_type: error.type
    )

    # Return structured compensation result
    {:ok,
     %{
       compensated: true,
       original_error: %{
         type: error.type,
         message: error.message
       },
       compensated_at: DateTime.utc_now(),
       request_id: request_id
     }}
  end

  # Private helpers

  defp generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end
end
