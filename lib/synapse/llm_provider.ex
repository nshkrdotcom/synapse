defmodule Synapse.LLMProvider do
  @moduledoc """
  Behaviour defining the contract for LLM provider adapters.

  Each provider (OpenAI, Gemini, Claude, etc.) implements this behaviour to handle
  provider-specific request/response formats while ReqLLM acts as a coordinator.

  ## Example

      defmodule Synapse.Providers.OpenAI do
        @behaviour Synapse.LLMProvider

        @impl true
        def prepare_body(params, profile_config, global_config) do
          # Build OpenAI-specific payload
          %{
            "model" => profile_config[:model],
            "messages" => build_messages(params, profile_config, global_config)
          }
        end

        @impl true
        def parse_response(response, _metadata) do
          # Parse OpenAI response format
          with [%{"message" => %{"content" => content}} | _] <- response.body["choices"] do
            {:ok, %{content: content, metadata: %{...}}}
          end
        end

        # ... other callbacks
      end
  """

  alias Jido.Error

  @typedoc """
  Response data structure returned by providers.

  All providers must normalize their responses into this structure.
  """
  @type response_data :: %{
          content: String.t(),
          metadata: %{
            optional(:provider_id) => String.t(),
            optional(:total_tokens) => non_neg_integer(),
            optional(:prompt_tokens) => non_neg_integer(),
            optional(:completion_tokens) => non_neg_integer(),
            optional(:finish_reason) => String.t(),
            optional(atom()) => any()
          }
        }

  @typedoc """
  Request metadata that can be used during response parsing.

  Providers can use this to pass contextual information from request
  construction to response parsing (e.g., model name, request ID).
  """
  @type request_metadata :: %{
          optional(:model) => String.t(),
          optional(:profile) => atom(),
          optional(atom()) => any()
        }

  @doc """
  Prepares the request body for the provider's API.

  Takes the user parameters, profile configuration, and global configuration
  and returns a map representing the JSON body to send to the provider.

  ## Parameters

    * `params` - User-provided parameters (messages, temperature, max_tokens, etc.)
    * `profile_config` - Profile-specific configuration (keyword list)
    * `global_config` - Global LLM configuration (map)

  ## Returns

    * A map representing the JSON request body
  """
  @callback prepare_body(
              params :: map(),
              profile_config :: keyword(),
              global_config :: map()
            ) :: map()

  @doc """
  Parses the provider's response into normalized format.

  Takes the HTTP response and request metadata, returning either a normalized
  response structure or an error.

  ## Parameters

    * `response` - The `Req.Response` struct from the HTTP client
    * `metadata` - Request metadata from `prepare_body/3` (e.g., model, profile)

  ## Returns

    * `{:ok, response_data}` - Successfully parsed response
    * `{:error, Jido.Error.t()}` - Parsing failed or response format invalid
  """
  @callback parse_response(
              response :: Req.Response.t(),
              metadata :: request_metadata()
            ) :: {:ok, response_data()} | {:error, Error.t()}

  @doc """
  Translates provider-specific errors into Jido.Error format.

  Takes an HTTP response with error status or a transport error and converts
  it into a user-friendly Jido.Error with appropriate type and details.

  ## Parameters

    * `response_or_error` - Either a `Req.Response` with error status or an error tuple
    * `metadata` - Request metadata for context (profile name, model, etc.)

  ## Returns

    * `Jido.Error.t()` with appropriate type (:execution_error, :config_error, etc.)
  """
  @callback translate_error(
              response_or_error :: Req.Response.t() | {:error, term()},
              metadata :: request_metadata()
            ) :: Error.t()

  @doc """
  Returns the list of features supported by this provider.

  Features may include:
  - `:streaming` - Server-sent events support
  - `:json_mode` - Structured JSON output
  - `:function_calling` - Tool/function invocation
  - `:vision` - Image input support
  - `:system_messages` - Native system message support

  ## Returns

    * List of supported feature atoms
  """
  @callback supported_features() :: [atom()]

  @doc """
  Returns the default configuration for this provider.

  Provides sensible defaults that can be overridden by user configuration.

  ## Returns

    * Keyword list of default configuration values
  """
  @callback default_config() :: keyword()

  @optional_callbacks [supported_features: 0, default_config: 0]
end
