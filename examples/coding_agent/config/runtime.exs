import Config

# Check provider availability from environment
config :coding_agent,
  claude_available: System.get_env("ANTHROPIC_API_KEY") != nil,
  codex_available: System.get_env("OPENAI_API_KEY") != nil,
  gemini_available: System.get_env("GEMINI_API_KEY") != nil

# Gemini configuration
if api_key = System.get_env("GEMINI_API_KEY") do
  config :gemini_ex, api_key: api_key
end

# Claude configuration (uses CLI auth by default, or API key)
if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :claude_agent_sdk, api_key: api_key
end

# Codex configuration
if api_key = System.get_env("OPENAI_API_KEY") do
  config :codex_sdk, api_key: api_key
end
