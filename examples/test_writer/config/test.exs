import Config

# Test configuration
config :test_writer,
  max_fix_attempts: 2,
  compile_timeout: 5_000,
  test_timeout: 10_000

# Use mock providers in tests
config :test_writer,
  provider_module: TestWriter.Providers.Mock

config :logger, level: :warning
