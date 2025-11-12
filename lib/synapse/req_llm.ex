defmodule Synapse.ReqLLM do
  @moduledoc """
  Thin wrapper around Req for issuing chat-completion requests to multiple LLM providers.

  Configuration lives under `:synapse, #{inspect(__MODULE__)}` and supports:

    * `:profiles` – map of named provider profiles (e.g. `%{openai: [...], gemini: [...]}`)
    * `:default_profile` – atom name of the default profile (optional)
    * `:system_prompt` – global fallback system prompt
    * `:default_model` – global fallback model identifier

  Each profile accepts:

    * `:base_url` – required API base URL
    * `:api_key` – required bearer/API key
    * `:model` – default model for the profile
    * `:allowed_models` – whitelist of permitted models (optional)
    * `:system_prompt` – profile-specific system prompt
    * `:endpoint` – request path (defaults to `/v1/chat/completions`, supports `"{model}"` token)
    * `:req_options` – additional Req options (defaults: connect_timeout: 5000, pool_timeout: 5000, receive_timeout: 600000)
    * `:retry` – retry configuration (see below)
    * `:plug`, `:plug_owner` – Req.Test settings for tests
    * `:temperature`, `:max_tokens` – profile-level defaults

  ## System Prompt Precedence

  System prompts are resolved in this order (highest to lowest priority):

  1. **Request-level system messages** - Messages with `role: "system"` in `params.messages`
  2. **Profile-level** - `:system_prompt` in profile configuration
  3. **Global-level** - `:system_prompt` in global configuration
  4. **Default** - `"You are a helpful assistant."`

  Example showing precedence:

      # Config has global and profile prompts
      config :synapse, Synapse.ReqLLM,
        system_prompt: "Global: You are helpful",
        profiles: %{
          openai: [
            system_prompt: "Profile: You are a code reviewer"  # ← Wins over global
          ]
        }

      # Request with system message
      ReqLLM.chat_completion(
        %{
          prompt: "Review this",
          messages: [
            %{role: "system", content: "Request: You are a Rust expert"}  # ← Preserved
          ]
        },
        profile: :openai
      )

  **OpenAI behavior:** Both base prompt and request system messages sent in messages array.
  **Gemini behavior:** Base prompt + request system messages merged into `system_instruction` field.

  See `Synapse.ReqLLM.SystemPrompt` for resolution logic.

  ## Retry Configuration

  Profiles can specify retry behavior for transient failures:

      retry: [
        max_attempts: 3,           # Total attempts (default: 3)
        base_backoff_ms: 300,      # Initial backoff in ms (default: 300)
        max_backoff_ms: 5_000,     # Maximum backoff in ms (default: 5000)
        enabled: true              # Enable/disable retries (default: true)
      ]

  Retries are triggered for:
  - HTTP 408 (Request Timeout)
  - HTTP 429 (Rate Limited)
  - HTTP 5xx (Server Errors)

  Uses exponential backoff with jitter: `base * (2^attempt) + random_jitter`

  ## Per-Request Options

  The `chat_completion/2` function accepts options to override profile defaults:

    * `:profile` – atom name of the profile to use
    * `:model` – model identifier to use for this request
    * `:temperature` – sampling temperature for this request
    * `:max_tokens` – maximum tokens for this request
    * `:timeout` or `:receive_timeout` – override receive timeout in milliseconds
    * `:connect_timeout` – override connect timeout in milliseconds
    * `:pool_timeout` – override pool timeout in milliseconds

  ## Telemetry

  This module emits telemetry events for observability:

    * `[:synapse, :llm, :request, :start]` - Request started
    * `[:synapse, :llm, :request, :stop]` - Request completed successfully
    * `[:synapse, :llm, :request, :exception]` - Request failed

  See `docs/20251028/remediation/telemetry_documentation.md` for details on attaching handlers.
  """

  alias Jido.Error
  alias Synapse.ReqLLM.Options

  @type message :: %{required(:role) => String.t(), required(:content) => String.t()}

  @default_model "gpt-4o-mini"
  @profile_key_map %{
    "base_url" => :base_url,
    "api_key" => :api_key,
    "model" => :model,
    "allowed_models" => :allowed_models,
    "system_prompt" => :system_prompt,
    "plug" => :plug,
    "plug_owner" => :plug_owner,
    "endpoint" => :endpoint,
    "req_options" => :req_options,
    "temperature" => :temperature,
    "max_tokens" => :max_tokens,
    "auth_header" => :auth_header,
    "auth_header_prefix" => :auth_header_prefix
  }

  @spec chat_completion(map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def chat_completion(params, opts \\ []) when is_map(params) and is_list(opts) do
    request_id = generate_request_id()
    start_time = System.monotonic_time()

    with {:ok, config} <- fetch_config(),
         {:ok, profile_name, profile_config} <- resolve_profile(config, opts),
         {:ok, model} <- resolve_model(profile_name, profile_config, config, opts) do
      # Emit start telemetry event
      :telemetry.execute(
        [:synapse, :llm, :request, :start],
        %{system_time: System.system_time()},
        %{
          request_id: request_id,
          profile: profile_name,
          model: model,
          provider: determine_provider(profile_config)
        }
      )

      # Resolve provider module
      provider_module = resolve_provider_module(profile_config)

      # Execute the request
      result =
        with {:ok, request} <- build_request(profile_config),
             {:ok, response} <-
               execute_request(
                 request,
                 params,
                 config,
                 profile_name,
                 profile_config,
                 model,
                 opts,
                 provider_module
               ) do
          parse_response(response, profile_name, model, provider_module)
        end

      # Emit appropriate telemetry based on result
      case result do
        {:ok, response_data} ->
          duration = System.monotonic_time() - start_time
          token_usage = extract_token_usage(response_data)

          :telemetry.execute(
            [:synapse, :llm, :request, :stop],
            %{duration: duration},
            %{
              request_id: request_id,
              profile: profile_name,
              model: model,
              provider: determine_provider(profile_config),
              token_usage: token_usage,
              finish_reason: get_in(response_data, [:metadata, :finish_reason])
            }
          )

          {:ok, response_data}

        {:error, error} ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:synapse, :llm, :request, :exception],
            %{duration: duration},
            %{
              request_id: request_id,
              profile: profile_name,
              model: model,
              provider: determine_provider(profile_config),
              error_type: error.type,
              error_message: error.message
            }
          )

          {:error, error}
      end
    else
      {:error, error} ->
        # Configuration or early validation errors - emit exception without profile info
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:synapse, :llm, :request, :exception],
          %{duration: duration},
          %{
            request_id: request_id,
            error_type: error.type,
            error_message: error.message
          }
        )

        {:error, error}
    end
  end

  ## Configuration helpers

  defp resolve_provider_module(profile_config) do
    case Keyword.get(profile_config, :provider_module) do
      nil ->
        # Fall back to payload_format for backwards compatibility
        case Keyword.get(profile_config, :payload_format) do
          :google_generate_content -> Synapse.Providers.Gemini
          :openai -> Synapse.Providers.OpenAI
          _ -> Synapse.Providers.OpenAI
        end

      module when is_atom(module) ->
        module
    end
  end

  defp fetch_config do
    case Application.get_env(:synapse, __MODULE__) do
      nil ->
        {:error, Error.config_error("Synapse.ReqLLM configuration is missing")}

      config when is_list(config) ->
        normalize_config(config)

      _ ->
        {:error, Error.config_error("Synapse.ReqLLM configuration must be a keyword list")}
    end
  end

  defp normalize_config(config) do
    # Handle legacy single-profile format (backwards compatibility)
    config =
      if Keyword.has_key?(config, :base_url) and not Keyword.has_key?(config, :profiles) do
        # Legacy format: convert to profiles format
        profile_keys = [
          :base_url,
          :api_key,
          :model,
          :allowed_models,
          :system_prompt,
          :plug,
          :plug_owner,
          :endpoint,
          :req_options,
          :temperature,
          :max_tokens,
          :retry,
          :payload_format,
          :provider_module,
          :auth_header,
          :auth_header_prefix
        ]

        profile = Keyword.take(config, profile_keys)
        global_keys = [:system_prompt, :default_model]

        config
        |> Keyword.drop(profile_keys)
        |> Keyword.take(global_keys)
        |> Keyword.put(:profiles, default: profile)
        |> Keyword.put(:default_profile, :default)
      else
        # Convert map profiles to keyword list if needed
        if profiles = Keyword.get(config, :profiles) do
          if is_map(profiles) do
            Keyword.put(config, :profiles, Map.to_list(profiles))
          else
            config
          end
        else
          config
        end
      end

    # Validate using NimbleOptions
    case Options.validate_global(config) do
      {:ok, validated} ->
        # Convert validated keyword list profiles to map for backwards compatibility
        profiles = Keyword.get(validated, :profiles, []) |> Map.new()

        {:ok,
         %{
           profiles: profiles,
           default_profile: Keyword.get(validated, :default_profile),
           system_prompt: Keyword.get(validated, :system_prompt),
           default_model: Keyword.get(validated, :default_model)
         }}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Error.config_error("Synapse.ReqLLM: #{Exception.message(error)}")}

      {:error, message} ->
        {:error, Error.config_error("Synapse.ReqLLM: #{message}")}
    end
  end

  defp resolve_profile(config, opts) do
    profiles = config.profiles

    raw_profile =
      Keyword.get(opts, :profile) ||
        config.default_profile ||
        Map.keys(profiles) |> List.first()

    with {:ok, profile_key} <- normalize_profile(raw_profile, profiles),
         {:ok, profile_config} <- Map.fetch(profiles, profile_key) do
      {:ok, profile_key, normalize_profile_config(profile_config)}
    else
      {:error, error} -> {:error, error}
      :error -> {:error, Error.config_error("Unknown LLM profile #{inspect(raw_profile)}")}
    end
  end

  defp normalize_profile(nil, profiles), do: {:ok, Map.keys(profiles) |> List.first()}

  defp normalize_profile(profile, profiles) when is_atom(profile) do
    if Map.has_key?(profiles, profile) do
      {:ok, profile}
    else
      {:error,
       Error.config_error(
         "Unknown LLM profile #{inspect(profile)}. Available profiles: #{available_profiles(profiles)}"
       )}
    end
  end

  defp normalize_profile(profile, profiles) when is_binary(profile) do
    downcased = String.downcase(profile)

    profiles
    |> Map.keys()
    |> Enum.find(fn key -> String.downcase(Atom.to_string(key)) == downcased end)
    |> case do
      nil ->
        {:error,
         Error.config_error(
           "Unknown LLM profile #{inspect(profile)}. Available profiles: #{available_profiles(profiles)}"
         )}

      key ->
        {:ok, key}
    end
  end

  defp available_profiles(profiles) do
    profiles
    |> Map.keys()
    |> Enum.map(&inspect/1)
    |> Enum.join(", ")
  end

  defp normalize_profile_config(profile_config) do
    profile_config
    |> Enum.reduce([], fn {key, value}, acc ->
      atom_key =
        cond do
          is_atom(key) ->
            key

          is_binary(key) ->
            Map.get(@profile_key_map, key) ||
              raise ArgumentError,
                    "Unknown profile configuration key #{inspect(key)}. Supported keys: #{Enum.join(Map.keys(@profile_key_map), ", ")}"
        end

      [{atom_key, value} | acc]
    end)
    |> Enum.reverse()
  end

  defp resolve_model(profile_name, profile_config, config, opts) do
    profile_map = Map.new(profile_config)

    candidate =
      Keyword.get(opts, :model) ||
        Map.get(profile_map, :model) ||
        Map.get(config, :default_model) ||
        @default_model

    allowed = Map.get(profile_map, :allowed_models)

    if allowed && candidate not in allowed do
      {:error,
       Error.config_error(
         "Model #{inspect(candidate)} is not allowed for profile #{profile_name}. Allowed models: #{Enum.map_join(allowed, ", ", &inspect/1)}"
       )}
    else
      {:ok, candidate}
    end
  end

  ## Request construction

  defp build_request(profile_config) do
    with {:ok, base_url} <- fetch_required(profile_config, :base_url),
         {:ok, api_key} <- fetch_required(profile_config, :api_key) do
      req_options =
        profile_config
        |> Keyword.get(:req_options, [])
        |> Keyword.merge(base_url: base_url)
        |> maybe_put_kw(:plug, Keyword.get(profile_config, :plug))

      retry_config = build_retry_config(profile_config)

      request =
        req_options
        |> Req.new()
        |> Req.Request.put_header("content-type", "application/json")
        |> put_api_key_header(api_key, profile_config)
        |> maybe_add_retry(retry_config)

      {:ok, request}
    end
  end

  defp execute_request(
         request,
         params,
         config,
         profile_name,
         profile_config,
         model,
         opts,
         provider_module
       ) do
    maybe_allow_req_test(profile_config)

    # Merge model and other runtime params into params for provider
    enhanced_params =
      params
      |> Map.put(:model, model)
      |> maybe_put_runtime_param(:temperature, Keyword.get(opts, :temperature))
      |> maybe_put_runtime_param(:max_tokens, Keyword.get(opts, :max_tokens))

    # Enhanced profile config with model
    enhanced_profile_config = Keyword.put(profile_config, :model, model)

    # Delegate payload construction to provider
    body = provider_module.prepare_body(enhanced_params, enhanced_profile_config, config)

    endpoint =
      profile_config
      |> Keyword.get(:endpoint, "/v1/chat/completions")
      |> String.replace("{model}", model)

    # Apply per-request timeout overrides
    request_opts = build_request_options(opts)

    request_metadata = %{profile: profile_name, model: model}

    case Req.post(request, [url: endpoint, json: body] ++ request_opts) do
      {:ok, %Req.Response{} = response} ->
        {:ok, response}

      {:error, %Req.TransportError{} = error} ->
        {:error,
         provider_module.translate_error({:transport_error, error.reason}, request_metadata)}

      {:error, %Mint.TransportError{} = error} ->
        {:error,
         provider_module.translate_error({:transport_error, error.reason}, request_metadata)}

      {:error, exception} when is_exception(exception) ->
        {:error,
         provider_module.translate_error(
           {:exception, Exception.message(exception)},
           request_metadata
         )}

      {:error, other} ->
        {:error, provider_module.translate_error({:error, other}, request_metadata)}
    end
  end

  defp maybe_allow_req_test(profile_config) do
    case {Keyword.get(profile_config, :plug), Keyword.get(profile_config, :plug_owner)} do
      {{Req.Test, name}, owner} when is_pid(owner) and owner != self() ->
        _ = Req.Test.allow(name, owner, self())
        :ok

      _ ->
        :ok
    end
  end

  defp parse_response(response, profile_name, model, provider_module) do
    # Delegate parsing to the provider module
    metadata = %{profile: profile_name, model: model}
    provider_module.parse_response(response, metadata)
  end

  ## Utility helpers

  defp fetch_required(config, key) do
    case Keyword.fetch(config, key) do
      {:ok, value} when value not in [nil, ""] ->
        {:ok, value}

      _ ->
        {:error, Error.config_error("Synapse.ReqLLM missing required #{inspect(key)}")}
    end
  end

  defp maybe_put_kw(list, _key, nil), do: list
  defp maybe_put_kw(list, key, value), do: Keyword.put(list, key, value)

  defp put_api_key_header(request, api_key, profile_config) do
    header = Keyword.get(profile_config, :auth_header)
    prefix = auth_prefix(header, profile_config)
    header_name = header || "authorization"

    value =
      case prefix do
        nil -> api_key
        prefix -> prefix <> api_key
      end

    Req.Request.put_header(request, header_name, value)
  end

  defp auth_prefix(nil, profile_config) do
    Keyword.get(profile_config, :auth_header_prefix, "Bearer ")
  end

  defp auth_prefix(_header, profile_config) do
    Keyword.get(profile_config, :auth_header_prefix)
  end

  ## Runtime parameter helpers

  defp maybe_put_runtime_param(map, _key, nil), do: map
  defp maybe_put_runtime_param(map, key, value), do: Map.put(map, key, value)

  ## Retry configuration helpers

  defp build_retry_config(profile_config) do
    retry_opts = Keyword.get(profile_config, :retry, [])

    %{
      max_attempts: Keyword.get(retry_opts, :max_attempts, 3),
      base_backoff_ms: Keyword.get(retry_opts, :base_backoff_ms, 300),
      max_backoff_ms: Keyword.get(retry_opts, :max_backoff_ms, 5_000),
      enabled: Keyword.get(retry_opts, :enabled, true)
    }
  end

  defp maybe_add_retry(request, %{enabled: false}), do: request

  defp maybe_add_retry(request, retry_config) do
    Req.Request.register_options(request, [:retry, :retry_delay, :max_retries])

    retry_opts = [
      retry: &should_retry?/2,
      retry_delay: fn attempt -> calculate_backoff(attempt, retry_config) end,
      max_retries: retry_config.max_attempts - 1
    ]

    Req.Request.merge_options(request, retry_opts)
  end

  # Req 0.5+ uses 2-arity retry function: retry(request, response_or_exception)
  defp should_retry?(_request, %{status: status}) when status in [408, 429] or status >= 500,
    do: true

  defp should_retry?(_request, _response), do: false

  defp calculate_backoff(attempt, config) do
    # Exponential backoff with jitter: base * (2 ^ attempt) + random jitter
    base_delay = config.base_backoff_ms * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(config.base_backoff_ms)
    delay = trunc(base_delay + jitter)

    min(delay, config.max_backoff_ms)
  end

  ## Request option helpers

  defp build_request_options(opts) do
    # Extract timeout-related options that can be overridden per-request
    []
    |> maybe_put_timeout(:receive_timeout, Keyword.get(opts, :receive_timeout))
    |> maybe_put_timeout(:receive_timeout, Keyword.get(opts, :timeout))
    |> maybe_put_timeout(:connect_timeout, Keyword.get(opts, :connect_timeout))
    |> maybe_put_timeout(:pool_timeout, Keyword.get(opts, :pool_timeout))
  end

  defp maybe_put_timeout(opts, _key, nil), do: opts

  defp maybe_put_timeout(opts, key, value) when is_integer(value) and value > 0 do
    Keyword.put(opts, key, value)
  end

  defp maybe_put_timeout(opts, _key, _value), do: opts

  ## Telemetry helpers

  defp generate_request_id do
    # Generate a unique request ID for tracking
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end

  defp determine_provider(profile_config) do
    case Keyword.get(profile_config, :payload_format) do
      :google_generate_content -> :gemini
      :openai -> :openai
      _ -> :openai
    end
  end

  defp extract_token_usage(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, :total_tokens) do
      total when is_integer(total) ->
        %{
          total_tokens: total,
          prompt_tokens: nil,
          completion_tokens: nil
        }

      _ ->
        nil
    end
  end

  defp extract_token_usage(_), do: nil
end
