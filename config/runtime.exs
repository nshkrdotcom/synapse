import Config

openai_key = System.get_env("OPENAI_API_KEY")
gemini_key = System.get_env("GEMINI_API_KEY")

profiles = %{}

profiles =
  if openai_key do
    Map.put(profiles, :openai,
      base_url: "https://api.openai.com",
      api_key: openai_key,
      model: "gpt-5-nano",
      allowed_models: ["gpt-5-nano"],
      temperature: 1.0,
      req_options: [
        receive_timeout: 600_000
      ]
    )
  else
    profiles
  end

profiles =
  if gemini_key do
    Map.put(profiles, :gemini,
      base_url: "https://generativelanguage.googleapis.com",
      api_key: gemini_key,
      model: "gemini-flash-lite-latest",
      endpoint: "/v1beta/models/{model}:generateContent",
      payload_format: :google_generate_content,
      auth_header: "x-goog-api-key",
      auth_header_prefix: nil,
      req_options: [
        receive_timeout: 30_000
      ]
    )
  else
    profiles
  end

if map_size(profiles) > 0 do
  default_profile =
    if Map.has_key?(profiles, :openai) do
      :openai
    else
      Map.keys(profiles) |> List.first()
    end

  config :synapse, Synapse.ReqLLM,
    default_profile: default_profile,
    profiles: profiles
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.
if config_env() == :prod do
  config :synapse, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing. Example: ecto://USER:PASS@HOST/DATABASE"

  config :synapse, Synapse.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    ssl: String.downcase(System.get_env("DATABASE_SSL", "false")) == "true"
end
