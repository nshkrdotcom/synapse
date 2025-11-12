defmodule Synapse.Providers.Gemini do
  @moduledoc """
  Google Gemini provider adapter for chat completion requests.

  Implements the `Synapse.LLMProvider` behaviour for Google's Gemini API format.
  Supports models like gemini-flash-lite, gemini-pro, etc.

  ## Configuration

      config :synapse, Synapse.ReqLLM,
        profiles: %{
          gemini: [
            base_url: "https://generativelanguage.googleapis.com",
            api_key: System.get_env("GEMINI_API_KEY"),
            model: "gemini-flash-lite-latest",
            endpoint: "/v1beta/models/{model}:generateContent",
            payload_format: :google_generate_content,
            auth_header: "x-goog-api-key",
            auth_header_prefix: nil,
            provider_module: Synapse.Providers.Gemini
          ]
        }

  ## Gemini-Specific Behavior

  - System prompts are sent via `system_instruction` field (separate from messages)
  - Role mapping: "assistant" → "model", "user" → "user"
  - System messages are extracted and merged into system_instruction
  - Uses `generationConfig` for temperature and maxOutputTokens
  """

  @behaviour Synapse.LLMProvider

  alias Jido.Error
  alias Synapse.ReqLLM.SystemPrompt

  @impl true
  def prepare_body(params, profile_config, global_config) do
    temperature = extract_param(params, profile_config, :temperature)
    max_tokens = extract_param(params, profile_config, :max_tokens)

    # Resolve base system prompt using shared precedence logic
    base_system_prompt = SystemPrompt.resolve(profile_config, global_config)

    normalized_messages =
      params
      |> Map.get(:messages, [])
      |> Enum.map(&normalize_message/1)

    # Extract system messages from request using shared helper
    {system_messages, dialog_messages} = SystemPrompt.extract_system_messages(normalized_messages)

    prompt_message = prompt_as_messages(params)

    # Convert to Gemini content format
    contents =
      dialog_messages
      |> Enum.concat(prompt_message)
      |> Enum.map(&to_gemini_content/1)
      |> ensure_content_present()

    # Merge base prompt with request-level system messages using shared helper
    system_instruction_text = SystemPrompt.merge(base_system_prompt, system_messages)

    base_body = %{"contents" => contents}

    base_body
    |> maybe_put("system_instruction", build_system_instruction(system_instruction_text))
    |> maybe_put("generationConfig", build_generation_config(temperature, max_tokens))
  end

  @impl true
  def parse_response(%Req.Response{status: status, body: body}, metadata)
      when status in 200..299 do
    candidates = Map.get(body, "candidates", [])

    with [%{} = candidate | _] <- candidates,
         {:ok, text} <- extract_gemini_text(candidate) do
      {:ok,
       %{
         content: text,
         metadata: %{
           provider_id: Map.get(candidate, "id"),
           total_tokens: get_in(body, ["usageMetadata", "totalTokenCount"]),
           prompt_tokens: get_in(body, ["usageMetadata", "promptTokenCount"]),
           completion_tokens: get_in(body, ["usageMetadata", "candidatesTokenCount"]),
           finish_reason: Map.get(candidate, "finishReason"),
           model: metadata[:model],
           provider: :gemini
         }
       }}
    else
      [] ->
        {:error,
         Error.execution_error(
           "Gemini response contained no candidates (content may have been blocked)",
           %{
             body: sanitize_body(body),
             profile: metadata[:profile],
             safety_ratings: get_in(body, ["promptFeedback", "safetyRatings"])
           }
         )}

      _ ->
        {:error,
         Error.execution_error(
           "Gemini response was missing expected 'candidates' field or content",
           %{
             body: sanitize_body(body),
             profile: metadata[:profile]
           }
         )}
    end
  end

  def parse_response(%Req.Response{status: status, body: body}, metadata) do
    {:error, translate_error({:http_error, status, body}, metadata)}
  end

  @impl true
  def translate_error({:http_error, status, body}, metadata) do
    profile_name = metadata[:profile] || "unknown"
    provider_message = extract_provider_message(body)

    message =
      case status do
        401 ->
          "Gemini request was unauthorized for profile #{profile_name}"

        403 ->
          "Gemini request was forbidden for profile #{profile_name}"

        429 ->
          "Gemini request was rate limited for profile #{profile_name}"

        status when status in 500..599 ->
          "Gemini API returned server error #{status} for profile #{profile_name}"

        _ ->
          "Gemini request returned #{status} for profile #{profile_name}"
      end

    message =
      if provider_message do
        message <> ": " <> provider_message
      else
        message
      end

    details =
      %{
        status: status,
        profile: profile_name,
        provider: :gemini,
        body: sanitize_body(body)
      }
      |> maybe_put(:provider_message, provider_message)

    Error.execution_error(message, details)
  end

  def translate_error({:transport_error, :timeout}, metadata) do
    profile_name = metadata[:profile] || "unknown"

    Error.execution_error(
      "Gemini request to profile #{profile_name} timed out. Verify connectivity or increase timeout.",
      %{profile: profile_name, provider: :gemini, reason: :timeout}
    )
  end

  def translate_error({:transport_error, reason}, metadata) do
    profile_name = metadata[:profile] || "unknown"

    Error.execution_error(
      "Gemini request to profile #{profile_name} failed due to #{humanize_reason(reason)}.",
      %{profile: profile_name, provider: :gemini, reason: reason}
    )
  end

  def translate_error(error, metadata) do
    profile_name = metadata[:profile] || "unknown"

    Error.execution_error(
      "Gemini request failed for profile #{profile_name}",
      %{profile: profile_name, provider: :gemini, reason: inspect(error)}
    )
  end

  @impl true
  def supported_features do
    [:streaming, :system_instruction, :safety_settings, :json_mode]
  end

  @impl true
  def default_config do
    [
      endpoint: "/v1beta/models/{model}:generateContent",
      payload_format: :google_generate_content,
      auth_header: "x-goog-api-key",
      auth_header_prefix: nil,
      req_options: [
        connect_timeout: 5_000,
        pool_timeout: 5_000,
        receive_timeout: 60_000
      ]
    ]
  end

  ## Private helpers

  defp normalize_message(%{role: role, content: content})
       when is_binary(role) and is_binary(content) do
    %{"role" => role, "content" => content}
  end

  defp normalize_message(%{"role" => role, "content" => content} = msg)
       when is_binary(role) and is_binary(content) do
    msg
  end

  defp normalize_message(other) do
    raise ArgumentError,
          "message must include :role/:content strings, got: #{inspect(other)}"
  end

  defp prompt_as_messages(%{prompt: prompt}) when is_binary(prompt) do
    [%{"role" => "user", "content" => prompt}]
  end

  defp prompt_as_messages(_), do: []

  defp to_gemini_content(%{"role" => role, "content" => content}) do
    %{
      "role" => gemini_role(role),
      "parts" => [%{"text" => content}]
    }
  end

  defp gemini_role(role) when role in ["model", "assistant"], do: "model"
  defp gemini_role(_), do: "user"

  defp ensure_content_present([]) do
    raise ArgumentError, "Gemini payload requires at least one message"
  end

  defp ensure_content_present(contents), do: contents

  defp build_system_instruction(nil), do: nil

  defp build_system_instruction(text) do
    %{"parts" => [%{"text" => text}]}
  end

  defp build_generation_config(nil, nil), do: nil

  defp build_generation_config(temperature, max_tokens) do
    %{}
    |> maybe_put("temperature", temperature)
    |> maybe_put("maxOutputTokens", max_tokens)
  end

  defp extract_gemini_text(candidate) do
    candidate
    |> Map.get("content")
    |> extract_gemini_content_text()
  end

  defp extract_gemini_content_text(%{"parts" => parts}) when is_list(parts) do
    parts
    |> Enum.find_value(&gemini_part_text/1)
    |> case do
      nil -> :error
      text -> {:ok, text}
    end
  end

  defp extract_gemini_content_text(_), do: :error

  defp gemini_part_text(%{"text" => text}) when is_binary(text), do: text
  defp gemini_part_text(_), do: nil

  defp extract_param(params, profile_config, key) do
    Map.get(params, key) || Keyword.get(profile_config, key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp extract_provider_message(body) when is_map(body) do
    get_string(body, ["error", "message"]) ||
      get_string(body, [:error, :message]) ||
      get_string(body, ["message"]) ||
      get_string(body, [:message])
  end

  defp extract_provider_message(_body), do: nil

  defp get_string(body, path) do
    case get_in(body, path) do
      value when is_binary(value) -> value
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp sanitize_body(body) when is_map(body) do
    # Limit body size in error details to prevent huge logs
    case Jason.encode(body) do
      {:ok, json} when byte_size(json) > 1000 ->
        %{truncated: String.slice(json, 0, 1000) <> "..."}

      {:ok, _json} ->
        body

      _ ->
        %{error: "Failed to encode response body"}
    end
  end

  defp sanitize_body(body), do: %{raw: inspect(body, limit: 500)}

  defp humanize_reason(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp humanize_reason(reason), do: inspect(reason)
end
