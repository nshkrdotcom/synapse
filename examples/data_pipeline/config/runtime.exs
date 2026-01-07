import Config

# Runtime configuration (loaded at application start)
if config_env() == :prod do
  config :data_pipeline,
    gemini_api_key: System.get_env("GEMINI_API_KEY"),
    gemini_available: !is_nil(System.get_env("GEMINI_API_KEY"))
end
