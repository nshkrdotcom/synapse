import Config

# Use mocks in test environment
config :data_pipeline,
  gemini_api_key: "test_key",
  gemini_available: true,
  use_mocks: true

# Smaller batches for faster tests
config :data_pipeline, DataPipeline.Batch,
  default_batch_size: 10,
  max_parallel_batches: 2

# Configure logger to show warnings and errors only
config :logger, level: :warning
