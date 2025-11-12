defmodule Synapse.Providers.OpenAI do
  @moduledoc """
  OpenAI provider adapter for chat completion requests.

  Implements the `Synapse.LLMProvider` behaviour for OpenAI's API format.
  Supports models like GPT-4, GPT-3.5-turbo, etc.

  ## Configuration

      config :synapse, Synapse.ReqLLM,
        profiles: %{
          openai: [
            base_url: "https://api.openai.com",
            api_key: System.get_env("OPENAI_API_KEY"),
            model: "gpt-4o-mini",
            provider_module: Synapse.Providers.OpenAI
          ]
        }
  """

  @behaviour Synapse.LLMProvider

  alias Jido.Error
  alias Synapse.ReqLLM.SystemPrompt

  @impl true
  def prepare_body(params, profile_config, global_config) do
    model = Keyword.get(profile_config, :model)
    temperature = extract_param(params, profile_config, :temperature)
    max_tokens = extract_param(params, profile_config, :max_tokens)

    params
    |> build_messages(profile_config, global_config)
    |> Map.put("model", model)
    |> maybe_put_number("temperature", temperature)
    |> maybe_put_number("max_completion_tokens", max_tokens)
  end

  @impl true
  def parse_response(%Req.Response{status: status, body: body}, metadata)
      when status in 200..299 do
    with [%{"message" => message} | _] <- Map.get(body, "choices", []),
         content when is_binary(content) <- Map.get(message, "content") do
      {:ok,
       %{
         content: content,
         metadata: %{
           provider_id: Map.get(body, "id"),
           total_tokens: get_in(body, ["usage", "total_tokens"]),
           prompt_tokens: get_in(body, ["usage", "prompt_tokens"]),
           completion_tokens: get_in(body, ["usage", "completion_tokens"]),
           finish_reason: Map.get(message, "finish_reason"),
           model: Map.get(body, "model"),
           provider: :openai
         }
       }}
    else
      _ ->
        {:error,
         Error.execution_error(
           "OpenAI response was missing expected 'choices' field",
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
          "OpenAI request was unauthorized for profile #{profile_name}"

        403 ->
          "OpenAI request was forbidden for profile #{profile_name}"

        429 ->
          "OpenAI request was rate limited for profile #{profile_name}"

        status when status in 500..599 ->
          "OpenAI API returned server error #{status} for profile #{profile_name}"

        _ ->
          "OpenAI request returned #{status} for profile #{profile_name}"
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
        provider: :openai,
        body: sanitize_body(body)
      }
      |> maybe_put(:provider_message, provider_message)

    Error.execution_error(message, details)
  end

  def translate_error({:transport_error, :timeout}, metadata) do
    profile_name = metadata[:profile] || "unknown"

    Error.execution_error(
      "OpenAI request to profile #{profile_name} timed out. Verify connectivity or increase timeout.",
      %{profile: profile_name, provider: :openai, reason: :timeout}
    )
  end

  def translate_error({:transport_error, reason}, metadata) do
    profile_name = metadata[:profile] || "unknown"

    Error.execution_error(
      "OpenAI request to profile #{profile_name} failed due to #{humanize_reason(reason)}.",
      %{profile: profile_name, provider: :openai, reason: reason}
    )
  end

  def translate_error(error, metadata) do
    profile_name = metadata[:profile] || "unknown"

    Error.execution_error(
      "OpenAI request failed for profile #{profile_name}",
      %{profile: profile_name, provider: :openai, reason: inspect(error)}
    )
  end

  @impl true
  def supported_features do
    [:streaming, :json_mode, :function_calling, :vision, :system_messages]
  end

  @impl true
  def default_config do
    [
      endpoint: "/v1/chat/completions",
      payload_format: :openai,
      auth_header: "authorization",
      auth_header_prefix: "Bearer ",
      req_options: [
        connect_timeout: 5_000,
        pool_timeout: 5_000,
        receive_timeout: 60_000
      ]
    ]
  end

  ## Private helpers

  defp build_messages(params, profile_config, global_config) do
    # Resolve base system prompt using shared precedence logic
    system_prompt = SystemPrompt.resolve(profile_config, global_config)
    base = [%{"role" => "system", "content" => system_prompt}]

    incoming =
      params
      |> Map.get(:messages, [])
      |> Enum.map(&normalize_message/1)

    prompt_message = prompt_as_messages(params)

    %{"messages" => base ++ incoming ++ prompt_message}
  end

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

  defp extract_param(params, profile_config, key) do
    Map.get(params, key) || Keyword.get(profile_config, key)
  end

  defp maybe_put_number(map, _key, nil), do: map
  defp maybe_put_number(map, key, value) when is_number(value), do: Map.put(map, key, value)
  defp maybe_put_number(map, _key, _value), do: map

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
