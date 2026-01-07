import Config

config :doc_generator,
  claude_available: System.get_env("ANTHROPIC_API_KEY") != nil,
  codex_available: System.get_env("OPENAI_API_KEY") != nil,
  gemini_available: System.get_env("GEMINI_API_KEY") != nil

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :workflow, :step]
