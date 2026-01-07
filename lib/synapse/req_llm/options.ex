defmodule Synapse.ReqLLM.Options do
  @moduledoc """
  NimbleOptions schemas for ReqLLM configuration validation.

  Provides compile-time validated configuration with auto-generated documentation.
  """

  @doc """
  Schema for retry configuration within a profile.
  """
  def retry_schema do
    [
      enabled: [
        type: :boolean,
        default: true,
        doc: "Enable or disable automatic retries for transient failures"
      ],
      max_attempts: [
        type: :pos_integer,
        default: 3,
        doc: "Total number of attempts including the initial request (must be >= 1)"
      ],
      base_backoff_ms: [
        type: :pos_integer,
        default: 300,
        doc: "Base backoff delay in milliseconds for exponential backoff"
      ],
      max_backoff_ms: [
        type: :pos_integer,
        default: 5_000,
        doc: "Maximum backoff delay in milliseconds (caps exponential growth)"
      ]
    ]
  end

  @doc """
  Schema for req_options within a profile.

  Note: We don't enforce a strict schema here because Req accepts many options.
  Users can pass any valid Req option through this field.
  """
  def req_options_schema do
    # Use :any to allow any keyword list through
    :any
  end

  @doc """
  Schema for an individual profile configuration.
  """
  def profile_schema do
    [
      base_url: [
        type: :string,
        required: true,
        doc: "Base URL for the LLM provider API (e.g., 'https://api.openai.com')"
      ],
      api_key: [
        type: :string,
        required: true,
        doc: "API key or authentication token for the provider"
      ],
      model: [
        type: :string,
        doc: "Default model to use for this profile (e.g., 'gpt-4o-mini')"
      ],
      allowed_models: [
        type: {:list, :string},
        doc: "Whitelist of allowed models for this profile (validates model param)"
      ],
      system_prompt: [
        type: :string,
        doc: "Profile-specific system prompt (overrides global system_prompt)"
      ],
      endpoint: [
        type: :string,
        default: "/v1/chat/completions",
        doc:
          "API endpoint path (supports {model} placeholder, e.g., '/v1beta/models/{model}:generateContent')"
      ],
      payload_format: [
        type: :atom,
        doc:
          "Legacy payload format identifier (:openai, :google_generate_content). Prefer :provider_module."
      ],
      provider_module: [
        type: :atom,
        doc:
          "Provider module implementing Synapse.LLMProvider behaviour (e.g., Synapse.Providers.OpenAI)"
      ],
      auth_header: [
        type: :string,
        default: "authorization",
        doc: "HTTP header name for authentication (e.g., 'x-goog-api-key' for Gemini)"
      ],
      auth_header_prefix: [
        type: {:or, [:string, nil]},
        default: "Bearer ",
        doc: "Prefix for auth header value (e.g., 'Bearer ' for OpenAI, nil for Gemini)"
      ],
      temperature: [
        type: {:or, [:float, :integer]},
        doc: "Default temperature for completions (0.0-2.0, provider-dependent)"
      ],
      max_tokens: [
        type: :pos_integer,
        doc: "Default maximum tokens to generate"
      ],
      retry: [
        type: :keyword_list,
        keys: retry_schema(),
        default: [],
        doc: "Retry configuration for transient failures (408, 429, 5xx)"
      ],
      req_options: [
        type: :keyword_list,
        default: [],
        doc: "Additional Req HTTP client options (timeouts, etc.). Accepts any valid Req options."
      ],
      plug: [
        type: {:tuple, [:atom, :atom]},
        doc: "Req.Test plug for testing (internal use)"
      ],
      plug_owner: [
        type: :pid,
        doc: "Req.Test plug owner PID (internal use)"
      ]
    ]
  end

  @doc """
  Schema for global ReqLLM configuration.
  """
  def global_schema do
    [
      profiles: [
        type: :keyword_list,
        required: true,
        doc: "Map of profile names to profile configurations"
      ],
      default_profile: [
        type: :atom,
        doc: "Default profile to use when not specified in request options"
      ],
      system_prompt: [
        type: :string,
        doc: "Global fallback system prompt used when profile doesn't specify one"
      ],
      default_model: [
        type: :string,
        doc: "Global fallback model when neither profile nor request specifies one"
      ]
    ]
  end

  @doc """
  Validates global configuration using NimbleOptions.

  Returns `{:ok, validated_config}` or `{:error, %NimbleOptions.ValidationError{}}`.
  """
  def validate_global(config) when is_list(config) do
    case NimbleOptions.validate(config, global_schema()) do
      {:ok, validated} ->
        # Validate each profile
        validate_profiles(validated)

      {:error, _} = error ->
        error
    end
  end

  def validate_global(config) do
    {:error, "Configuration must be a keyword list, got: #{inspect(config)}"}
  end

  @doc """
  Validates global configuration, raising on error.
  """
  def validate_global!(config) do
    case validate_global(config) do
      {:ok, validated} ->
        validated

      {:error, %NimbleOptions.ValidationError{} = error} ->
        raise ArgumentError, """
        Invalid Synapse.ReqLLM configuration:

        #{Exception.message(error)}

        See module documentation for valid configuration options.
        """

      {:error, message} ->
        raise ArgumentError, message
    end
  end

  @doc """
  Validates a single profile configuration.
  """
  def validate_profile(profile_config) when is_list(profile_config) do
    NimbleOptions.validate(profile_config, profile_schema())
  end

  def validate_profile(profile_config) do
    {:error, "Profile configuration must be a keyword list, got: #{inspect(profile_config)}"}
  end

  defp validate_profiles(config) do
    profiles = Keyword.get(config, :profiles, [])

    Enum.reduce_while(profiles, {:ok, config}, fn {name, profile_config}, {:ok, acc} ->
      case validate_profile(profile_config) do
        {:ok, validated_profile} ->
          {:cont, {:ok, put_validated_profile(acc, name, validated_profile)}}

        {:error, %NimbleOptions.ValidationError{} = error} ->
          {:halt, {:error, profile_error(name, error)}}

        {:error, message} ->
          {:halt, {:error, "Profile #{inspect(name)}: #{message}"}}
      end
    end)
  end

  defp put_validated_profile(config, name, validated_profile) do
    Keyword.update!(config, :profiles, fn profs ->
      Keyword.put(profs, name, validated_profile)
    end)
  end

  defp profile_error(name, error) do
    NimbleOptions.ValidationError.exception(
      keys_path: [:profiles, name],
      message: error.message
    )
  end

  @doc """
  Returns documentation for all configuration options.

  Useful for generating help text or configuration guides.
  """
  def docs do
    """
    # Synapse.ReqLLM Configuration

    ## Global Options

    #{NimbleOptions.docs(global_schema())}

    ## Profile Options

    Each profile in `:profiles` accepts:

    #{NimbleOptions.docs(profile_schema())}

    ## Retry Options

    Within a profile's `:retry` configuration:

    #{NimbleOptions.docs(retry_schema())}

    ## Example Configuration

    ```elixir
    config :synapse, Synapse.ReqLLM,
      default_profile: :openai,
      system_prompt: "You are a helpful assistant",
      profiles: [
        openai: [
          base_url: "https://api.openai.com",
          api_key: System.get_env("OPENAI_API_KEY"),
          model: "gpt-4o-mini",
          allowed_models: ["gpt-4o-mini", "gpt-4"],
          retry: [
            max_attempts: 3,
            base_backoff_ms: 300
          ]
        ]
      ]
    ```
    """
  end
end
