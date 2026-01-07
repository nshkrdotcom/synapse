import Config

# Runtime configuration (loads environment variables)
if config_env() != :test do
  if api_key = System.get_env("OPENAI_API_KEY") do
    config :codex_sdk, api_key: api_key
  end
end
